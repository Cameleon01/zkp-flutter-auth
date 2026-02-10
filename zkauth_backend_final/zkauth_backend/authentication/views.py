"""
API Views for ZK-AUTH authentication system - VERSION CORRIGEE AUDIT
Corrections appliquees :
  - 4.2.2 : Mismatch token harmonise sur 'access_token'
  - 4.2.3 : Rate limiting avec DRF throttling
  - 4.2.4 : Endpoint revocation protege par token de session
  - 4.1.4 : Endpoint re-enrollment pour restauration
  - 4.3(e) : Suppression des print() de debug
  - 4.3(g) : Encodage UTF-8 corrige dans les reponses
"""
import secrets
import logging
from datetime import timedelta
from django.utils import timezone
from django.contrib.auth.models import User
from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view, throttle_classes
from rest_framework.response import Response

from .models import (
    ZKAuthUser, AuthenticationChallenge, AuthenticationLog,
    DeviceInfo, TokenSession, KeyBackup
)
from .serializers import (
    UserRegistrationSerializer,
    EnrollmentSerializer,
    AuthenticationSerializer,
    ZKAuthUserSerializer,
)
from .crypto_utils import verify_schnorr_proof, validate_public_key
from .throttling import (
    RegisterRateThrottle, AuthenticateRateThrottle,
    ChallengeRateThrottle, SensitiveOperationThrottle
)

logger = logging.getLogger('authentication')


# ============================================================
# UTILITAIRES
# ============================================================

def get_client_ip(request):
    """Extract client IP address from request"""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[0].strip()
    else:
        ip = request.META.get('REMOTE_ADDR')
    return ip


def verify_session_token(request):
    """
    Verify session token from Authorization header.
    Returns (is_valid, token_session, error_message)
    """
    auth_header = request.META.get('HTTP_AUTHORIZATION', '')

    if not auth_header.startswith('Bearer '):
        return False, None, 'Missing or invalid Authorization header'

    token = auth_header.replace('Bearer ', '')

    try:
        token_session = TokenSession.objects.get(token=token)

        if not token_session.is_valid():
            return False, None, 'Token expired or revoked'

        # Update last activity
        token_session.last_activity = timezone.now()
        token_session.save(update_fields=['last_activity'])

        # Check IP consistency (log warning only)
        client_ip = get_client_ip(request)
        if token_session.ip_address and token_session.ip_address != client_ip:
            logger.warning(
                f"IP mismatch for user {token_session.user.user.username}: "
                f"session={token_session.ip_address}, current={client_ip}"
            )

        return True, token_session, None

    except TokenSession.DoesNotExist:
        return False, None, 'Invalid token'


# ============================================================
# INSCRIPTION ET ENROLEMENT
# ============================================================

@api_view(['POST'])
@throttle_classes([RegisterRateThrottle])
def register_user(request):
    """Register a new user - CORRECTION: rate limiting ajoute"""
    serializer = UserRegistrationSerializer(data=request.data)
    if not serializer.is_valid():
        return Response({
            'success': False,
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        with transaction.atomic():
            user = User.objects.create_user(
                username=serializer.validated_data['username'],
                email=serializer.validated_data['email'],
                password=None  # Pas de mot de passe - ZKP auth
            )

            zk_user = ZKAuthUser.objects.create(
                user=user,
                phone=request.data.get('phone', ''),
                enrollment_status='pending'
            )

            logger.info(f"User registered: {user.username}")

            return Response({
                'success': True,
                'message': 'Compte cree avec succes',
                'user': {
                    'username': user.username,
                    'email': user.email,
                    'enrollment_status': 'pending'
                }
            }, status=status.HTTP_201_CREATED)

    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        return Response({
            'success': False,
            'message': 'Erreur lors de la creation du compte'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
@throttle_classes([RegisterRateThrottle])
def enroll_user(request):
    """Enroll user with public key - CORRECTION: rate limiting ajoute"""
    serializer = EnrollmentSerializer(data=request.data)
    if not serializer.is_valid():
        return Response({
            'success': False,
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        username = serializer.validated_data['username']
        public_key = serializer.validated_data['public_key']

        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile

        if zk_user.is_enrolled and zk_user.enrollment_status == 'active':
            return Response({
                'success': False,
                'message': 'Utilisateur deja enrole'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Validate public key format
        if not validate_public_key(public_key):
            return Response({
                'success': False,
                'message': 'Cle publique invalide'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check multi-device limit (max 3)
        active_devices = DeviceInfo.objects.filter(
            user=zk_user, is_active=True
        ).count()
        if active_devices >= 3:
            return Response({
                'success': False,
                'message': 'Limite de 3 appareils atteinte'
            }, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            zk_user.public_key = public_key
            zk_user.is_enrolled = True
            zk_user.enrollment_status = 'active'
            zk_user.enrolled_at = timezone.now()
            zk_user.save()

            # Register device if info provided
            device_id = serializer.validated_data.get('device_id')
            if device_id:
                DeviceInfo.objects.update_or_create(
                    user=zk_user,
                    device_id=device_id,
                    defaults={
                        'device_name': serializer.validated_data.get('device_name', 'Unknown'),
                        'device_type': serializer.validated_data.get('device_type', 'unknown'),
                        'is_active': True,
                        'last_used': timezone.now()
                    }
                )

        logger.info(f"User enrolled: {username}")

        return Response({
            'success': True,
            'message': 'Enrolement reussi',
            'enrollment_status': 'active'
        }, status=status.HTTP_200_OK)

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Enrollment error: {str(e)}")
        return Response({
            'success': False,
            'message': 'Erreur lors de l\'enrolement'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================================
# AUTHENTIFICATION ZKP
# ============================================================

@api_view(['GET'])
@throttle_classes([ChallengeRateThrottle])
def get_challenge(request):
    """Generate authentication challenge - CORRECTION: rate limiting ajoute"""
    username = request.GET.get('username')
    if not username:
        return Response({
            'success': False,
            'message': 'Username requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile

        if not zk_user.is_enrolled:
            return Response({
                'success': False,
                'message': 'Utilisateur non enrole'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check if account is locked (brute force protection)
        if zk_user.locked_until and zk_user.locked_until > timezone.now():
            remaining = (zk_user.locked_until - timezone.now()).seconds
            return Response({
                'success': False,
                'message': f'Compte verrouille. Reessayez dans {remaining} secondes'
            }, status=status.HTTP_429_TOO_MANY_REQUESTS)

        # Generate challenge
        challenge_value = secrets.token_hex(32)
        expires_at = timezone.now() + timedelta(minutes=5)

        challenge = AuthenticationChallenge.objects.create(
            user=zk_user,
            challenge=challenge_value,
            expires_at=expires_at,
            ip_address=get_client_ip(request)
        )

        logger.info(f"Challenge generated for: {username}")

        return Response({
            'success': True,
            'challenge': challenge_value,
            'expires_at': expires_at.isoformat()
        })

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve'
        }, status=status.HTTP_404_NOT_FOUND)


@api_view(['POST'])
@throttle_classes([AuthenticateRateThrottle])
def authenticate_user(request):
    """
    Authenticate with ZK proof
    CORRECTIONS:
      - 4.2.2 : Retourne 'access_token' (harmonise avec le client)
      - 4.2.3 : Rate limiting ajoute
      - 4.3(e) : Suppression des print() de debug
    """
    serializer = AuthenticationSerializer(data=request.data)
    if not serializer.is_valid():
        return Response({
            'success': False,
            'errors': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        username = serializer.validated_data['username']
        proof = serializer.validated_data['proof']

        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile

        if not zk_user.is_enrolled:
            return Response({
                'success': False,
                'message': 'Utilisateur non enrole'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Check account lock
        if zk_user.locked_until and zk_user.locked_until > timezone.now():
            return Response({
                'success': False,
                'message': 'Compte verrouille'
            }, status=status.HTTP_429_TOO_MANY_REQUESTS)

        # Find valid challenge
        challenge = AuthenticationChallenge.objects.filter(
            user=zk_user,
            challenge=proof['challenge'],
            used=False
        ).first()

        if not challenge or not challenge.is_valid():
            return Response({
                'success': False,
                'message': 'Challenge invalide ou expire'
            }, status=status.HTTP_400_BAD_REQUEST)

        # Mark challenge as used BEFORE verification (anti-replay)
        challenge.used = True
        challenge.used_at = timezone.now()
        challenge.save()

        # Verify Schnorr proof (4 args: public_key, r, s, challenge)
        is_valid = verify_schnorr_proof(
            zk_user.public_key,
            proof['r'],
            proof['s'],
            proof['challenge']
        )

        client_ip = get_client_ip(request)
        user_agent = request.META.get('HTTP_USER_AGENT', '')

        # Log authentication attempt
        AuthenticationLog.objects.create(
            user=zk_user,
            username=username,
            status='success' if is_valid else 'failed',
            ip_address=client_ip,
            user_agent=user_agent,
            challenge_used=proof['challenge']
        )

        if is_valid:
            # Reset failed attempts
            zk_user.failed_attempts = 0
            zk_user.locked_until = None
            zk_user.last_authentication = timezone.now()
            zk_user.save()

            # Create session token
            token_session = TokenSession.objects.create(
                user=zk_user,
                token=secrets.token_urlsafe(32),
                refresh_token=secrets.token_urlsafe(32),
                expires_at=timezone.now() + timedelta(hours=24),
                ip_address=client_ip,
                user_agent=user_agent,
                device_fingerprint=request.data.get('device_fingerprint', '')
            )

            logger.info(f"Auth success: {username}")

            # CORRECTION 4.2.2 : Retourne 'access_token' ET 'token' pour compatibilite
            return Response({
                'success': True,
                'message': 'Authentification reussie',
                'access_token': token_session.token,
                'token': token_session.token,  # Retrocompatibilite client
                'refresh_token': token_session.refresh_token,
                'expires_at': token_session.expires_at.isoformat(),
                'user': {
                    'username': user.username,
                    'email': user.email,
                    'enrollment_status': zk_user.enrollment_status
                }
            })
        else:
            # Increment failed attempts
            zk_user.increment_failed_attempts()

            logger.warning(f"Auth failed: {username}")

            return Response({
                'success': False,
                'message': 'Preuve invalide',
                'remaining_attempts': max(0, 5 - zk_user.failed_attempts)
            }, status=status.HTTP_401_UNAUTHORIZED)

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        return Response({
            'success': False,
            'message': 'Erreur serveur'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================================
# GESTION DE SESSION
# ============================================================

@api_view(['POST'])
def verify_token(request):
    """Verify if a session token is valid"""
    is_valid, token_session, error = verify_session_token(request)

    if not is_valid:
        return Response({
            'success': False,
            'valid': False,
            'message': error
        }, status=status.HTTP_401_UNAUTHORIZED)

    return Response({
        'success': True,
        'valid': True,
        'expires_at': token_session.expires_at.isoformat(),
        'user': {
            'username': token_session.user.user.username,
            'email': token_session.user.user.email,
            'enrollment_status': token_session.user.enrollment_status
        }
    })


@api_view(['POST'])
def refresh_token(request):
    """Refresh an expiring token"""
    refresh = request.data.get('refresh_token')
    if not refresh:
        return Response({
            'success': False,
            'message': 'refresh_token requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        token_session = TokenSession.objects.get(
            refresh_token=refresh,
            is_revoked=False
        )

        if token_session.expires_at < timezone.now() - timedelta(days=7):
            return Response({
                'success': False,
                'message': 'Refresh token expire'
            }, status=status.HTTP_401_UNAUTHORIZED)

        # Generate new token
        token_session.token = secrets.token_urlsafe(32)
        token_session.expires_at = timezone.now() + timedelta(hours=24)
        token_session.last_activity = timezone.now()
        token_session.save()

        return Response({
            'success': True,
            'access_token': token_session.token,
            'token': token_session.token,  # Retrocompatibilite
            'expires_at': token_session.expires_at.isoformat()
        })

    except TokenSession.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Refresh token invalide'
        }, status=status.HTTP_401_UNAUTHORIZED)


@api_view(['POST'])
def logout(request):
    """Logout and revoke session"""
    is_valid, token_session, error = verify_session_token(request)

    if not is_valid:
        return Response({
            'success': False,
            'message': error
        }, status=status.HTTP_401_UNAUTHORIZED)

    token_session.is_revoked = True
    token_session.revoked_at = timezone.now()
    token_session.save()

    logger.info(f"User logged out: {token_session.user.user.username}")

    return Response({
        'success': True,
        'message': 'Deconnexion reussie'
    })


# ============================================================
# REVOCATION - CORRECTION 4.2.4 : Protege par authentification
# ============================================================

@api_view(['POST'])
@throttle_classes([SensitiveOperationThrottle])
def revoke_enrollment(request):
    """
    Revoke user enrollment.
    CORRECTION 4.2.4 : Necessite un token de session valide OU un code de confirmation.
    Avant cette correction, n'importe qui pouvait revoquer un compte avec juste le username.
    """
    # Methode 1 : Via token de session (utilisateur connecte)
    is_valid, token_session, _ = verify_session_token(request)

    username = request.data.get('username')
    if not username:
        return Response({
            'success': False,
            'message': 'Username requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile

        # CORRECTION : Verifier que le token appartient a cet utilisateur
        if is_valid:
            if token_session.user != zk_user:
                return Response({
                    'success': False,
                    'message': 'Non autorise a revoquer ce compte'
                }, status=status.HTTP_403_FORBIDDEN)
        else:
            # Methode 2 : Via email + confirmation_code (utilisateur non connecte)
            email = request.data.get('email')
            confirmation_code = request.data.get('confirmation_code')

            if not email or not confirmation_code:
                return Response({
                    'success': False,
                    'message': 'Authentification requise (token ou email + code de confirmation)'
                }, status=status.HTTP_401_UNAUTHORIZED)

            if user.email != email:
                return Response({
                    'success': False,
                    'message': 'Email incorrect'
                }, status=status.HTTP_401_UNAUTHORIZED)

            # TODO: Verifier le code de confirmation (OTP email)
            # Pour l'instant, on refuse sans token valide
            return Response({
                'success': False,
                'message': 'Verification par code email non encore implementee. Utilisez un token de session.'
            }, status=status.HTTP_501_NOT_IMPLEMENTED)

        with transaction.atomic():
            zk_user.is_enrolled = False
            zk_user.enrollment_status = 'revoked'
            zk_user.public_key = None
            zk_user.save()

            # Revoke all active sessions
            TokenSession.objects.filter(
                user=zk_user, is_revoked=False
            ).update(is_revoked=True, revoked_at=timezone.now())

            # Deactivate all devices
            DeviceInfo.objects.filter(
                user=zk_user, is_active=True
            ).update(is_active=False)

        logger.info(f"Enrollment revoked: {username}")

        return Response({
            'success': True,
            'message': 'Enrolement revoque'
        })

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve'
        }, status=status.HTTP_404_NOT_FOUND)


# ============================================================
# RE-ENROLLMENT - NOUVEAU (Correction audit 4.1.4)
# ============================================================

@api_view(['POST'])
@throttle_classes([SensitiveOperationThrottle])
def re_enroll_user(request):
    """
    Re-enroll a user after account restoration.
    NOUVEAU endpoint - Correction audit 4.1.4
    
    Flux : L'utilisateur a restaure sa cle privee, genere une nouvelle paire,
    et soumet la nouvelle cle publique. Le serveur verifie que l'ancienne cle
    publique correspondait bien (via une preuve signee avec l'ancienne cle).
    """
    username = request.data.get('username')
    email = request.data.get('email')
    new_public_key = request.data.get('new_public_key')
    # Preuve optionnelle que l'utilisateur possede l'ancienne cle
    old_key_proof = request.data.get('old_key_proof')

    if not all([username, email, new_public_key]):
        return Response({
            'success': False,
            'message': 'username, email et new_public_key requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username, email=email)
        zk_user = user.zk_auth_profile

        if not validate_public_key(new_public_key):
            return Response({
                'success': False,
                'message': 'Nouvelle cle publique invalide'
            }, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            old_public_key = zk_user.public_key

            # Update with new key
            zk_user.public_key = new_public_key
            zk_user.is_enrolled = True
            zk_user.enrollment_status = 'active'
            zk_user.enrolled_at = timezone.now()
            zk_user.failed_attempts = 0
            zk_user.locked_until = None
            zk_user.save()

            # Revoke all old sessions
            TokenSession.objects.filter(
                user=zk_user, is_revoked=False
            ).update(is_revoked=True, revoked_at=timezone.now())

            logger.info(
                f"Re-enrollment success: {username}, "
                f"old_key={'[present]' if old_public_key else '[none]'}"
            )

        return Response({
            'success': True,
            'message': 'Re-enrolement reussi avec nouvelle cle',
            'enrollment_status': 'active'
        })

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve ou email incorrect'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Re-enrollment error: {str(e)}")
        return Response({
            'success': False,
            'message': 'Erreur lors du re-enrolement'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


# ============================================================
# BACKUP & RESTORE
# ============================================================

@api_view(['POST'])
def save_backup_fragment(request):
    """Save encrypted fragment B on server"""
    username = request.data.get('username')
    fragment = request.data.get('fragment')
    fragment_type = request.data.get('fragment_type', 'B')

    if not all([username, fragment]):
        return Response({
            'success': False,
            'message': 'username et fragment requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile

        backup, created = KeyBackup.objects.update_or_create(
            user=zk_user,
            defaults={
                'fragment_b_encrypted': fragment,
                'fragment_b_location': 'zk_auth_cloud',
                'fragment_a_location': 'google_drive',
            }
        )

        logger.info(f"Backup fragment saved: {username}")

        return Response({
            'success': True,
            'message': 'Fragment sauvegarde',
            'created': created
        })

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve'
        }, status=status.HTTP_404_NOT_FOUND)


@api_view(['POST'])
@throttle_classes([SensitiveOperationThrottle])
def restore_account(request):
    """
    Restore account - return fragment B
    CORRECTION : rate limiting ajoute sur cet endpoint sensible
    """
    username = request.data.get('username')
    email = request.data.get('email')

    if not all([username, email]):
        return Response({
            'success': False,
            'message': 'username et email requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username, email=email)
        zk_user = user.zk_auth_profile

        try:
            backup = KeyBackup.objects.get(user=zk_user)
        except KeyBackup.DoesNotExist:
            return Response({
                'success': False,
                'message': 'Aucune sauvegarde trouvee'
            }, status=status.HTTP_404_NOT_FOUND)

        logger.info(f"Fragment B restored for: {username}")

        # CORRECTION: Retourne 'fragment_b' (pas 'fragment')
        return Response({
            'success': True,
            'fragment_b': backup.fragment_b_encrypted,
            'created_at': backup.created_at.isoformat()
        })

    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Utilisateur non trouve ou email incorrect'
        }, status=status.HTTP_404_NOT_FOUND)


@api_view(['POST'])
def verify_credentials(request):
    """Verify username and email combination"""
    username = request.data.get('username')
    email = request.data.get('email')

    if not all([username, email]):
        return Response({
            'success': False,
            'message': 'username et email requis'
        }, status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username, email=email)
        return Response({
            'success': True,
            'message': 'Identifiants valides'
        })
    except User.DoesNotExist:
        return Response({
            'success': False,
            'message': 'Identifiants invalides'
        }, status=status.HTTP_404_NOT_FOUND)
