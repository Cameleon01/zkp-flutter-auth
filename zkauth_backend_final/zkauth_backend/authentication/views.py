"""
API Views for ZK-AUTH authentication system - CORRECTED VERSION
"""
import secrets
import logging
from datetime import timedelta
from django.utils import timezone
from django.contrib.auth.models import User
from django.db import transaction
from rest_framework import status
from rest_framework.decorators import api_view
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

logger = logging.getLogger('authentication')


def get_client_ip(request):
    """Extract client IP address from request"""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[0]
    else:
        ip = request.META.get('REMOTE_ADDR')
    return ip


def verify_session_token(request):
    """
    Verify session token from Authorization header
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
        
        # Check IP consistency (optional but recommended)
        client_ip = get_client_ip(request)
        if token_session.ip_address and token_session.ip_address != client_ip:
            logger.warning(f"IP mismatch for token: {token_session.ip_address} != {client_ip}")
            # Don't block, just log (mobile IPs can change)
        
        # Update last activity
        token_session.last_activity = timezone.now()
        token_session.save()
        
        return True, token_session, None
        
    except TokenSession.DoesNotExist:
        return False, None, 'Invalid token'


@api_view(['POST'])
def register_user(request):
    """
    Register a new user (Step 1: Basic account creation)
    
    POST /api/auth/register/
    {
        "username": "johndoe",
        "email": "john@example.com",
        "phone": "+229XXXXXXXX"
    }
    """
    serializer = UserRegistrationSerializer(data=request.data)
    
    if not serializer.is_valid():
        return Response({
            'success': False,
            'error': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        with transaction.atomic():
            # Create Django user
            user = User.objects.create_user(
                username=serializer.validated_data['username'],
                email=serializer.validated_data['email'],
            )
            
            # Create ZKAuthUser profile
            zk_user = ZKAuthUser.objects.create(
                user=user,
                # phone=serializer.validated_data['phone'],
                is_enrolled=False,
                enrollment_status='pending'
            )
            
            logger.info(f"User registered: {user.username}")
            
            return Response({
                'success': True,
                'message': 'Compte créé avec succès',
                'user': {
                    'id': zk_user.id,
                    'username': user.username,
                    'email': user.email,
                    # 'phone': zk_user.phone,
                    'is_enrolled': False
                }
            }, status=status.HTTP_201_CREATED)
            
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur lors de la création du compte'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def enroll_user(request):
    """
    Enroll user with ZK-AUTH (Step 2: Register public key)
    
    POST /api/auth/enroll/
    {
        "username": "johndoe",
        "public_key": "04a3b2c1d4e5f6...",
        "device_id": "optional-device-id",
        "device_name": "optional-device-name",
        "device_type": "android"
    }
    """
    serializer = EnrollmentSerializer(data=request.data)
    
    if not serializer.is_valid():
        return Response({
            'success': False,
            'error': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
    
    username = serializer.validated_data['username']
    public_key = serializer.validated_data['public_key']
    
    try:
        # Get user
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile
        
        # NEW: Check device limit (max 3 devices)
        active_devices_count = zk_user.devices.filter(is_active=True).count()
        
        if active_devices_count >= 3:
            return Response({
                'success': False,
                'error': 'Maximum 3 appareils autorisés. Révoquez un appareil existant.',
                'active_devices': list(
                    zk_user.devices.filter(is_active=True).values(
                        'device_name', 'device_id', 'enrolled_at', 'last_used'
                    )
                )
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if already enrolled
        if zk_user.is_enrolled:
            return Response({
                'success': False,
                'error': 'Utilisateur déjà enrôlé'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Validate public key format
        if not validate_public_key(public_key):
            return Response({
                'success': False,
                'error': 'Clé publique invalide'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        with transaction.atomic():
            # Update ZKAuthUser
            zk_user.public_key = public_key
            zk_user.is_enrolled = True
            zk_user.enrollment_status = 'active'
            zk_user.enrolled_at = timezone.now()
            zk_user.save()
            
            # Register device if provided
            device_id = serializer.validated_data.get('device_id')
            device_name = serializer.validated_data.get('device_name', 'Unknown Device')
            device_type = serializer.validated_data.get('device_type', 'unknown')
            
            if device_id:
                DeviceInfo.objects.create(
                    user=zk_user,
                    device_id=device_id,
                    device_name=device_name,
                    device_type=device_type,
                )
            
            logger.info(f"User enrolled: {username}")
            
            return Response({
                'success': True,
                'message': 'Enrôlement réussi',
                'user': ZKAuthUserSerializer(zk_user).data
            }, status=status.HTTP_200_OK)
            
    except User.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Enrollment error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur lors de l\'enrôlement'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['GET'])
def get_challenge(request):
    """
    Generate authentication challenge
    
    GET /api/auth/challenge/?username=johndoe
    """
    username = request.GET.get('username')
    
    if not username:
        return Response({
            'success': False,
            'error': 'Username requis'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile
        
        # Check if enrolled
        if not zk_user.is_enrolled:
            return Response({
                'success': False,
                'error': 'Utilisateur non enrôlé'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if account is locked
        if zk_user.is_locked():
            return Response({
                'success': False,
                'error': 'Compte temporairement verrouillé',
                'locked_until': zk_user.locked_until.isoformat()
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Generate random challenge (32 bytes = 64 hex chars)
        challenge_value = secrets.token_hex(32)
        client_ip = get_client_ip(request)
        
        # Create challenge record
        challenge = AuthenticationChallenge.objects.create(
            user=zk_user,
            challenge=challenge_value,
            expires_at=timezone.now() + timedelta(seconds=300),  # 5 minutes
            ip_address=client_ip
        )
        
        logger.info(f"🔑 Challenge generated for: {username}")
        
        return Response({
            'success': True,
            'challenge': challenge_value,
            'expires_in': 300
        }, status=status.HTTP_200_OK)
        
    except User.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Challenge generation error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur lors de la génération du challenge'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def authenticate_user(request):
    """
    Authenticate user with Zero-Knowledge proof
    
    POST /api/auth/authenticate/
    {
        "username": "johndoe",
        "proof": {
            "r": "04...",
            "s": "abc123...",
            "challenge": "def456..."
        },
        "device_fingerprint": "optional"
    }
    """
    serializer = AuthenticationSerializer(data=request.data)
    
    if not serializer.is_valid():
        return Response({
            'success': False,
            'error': serializer.errors
        }, status=status.HTTP_400_BAD_REQUEST)
    
    username = serializer.validated_data['username']
    proof_data = serializer.validated_data['proof']
    device_fingerprint = request.data.get('device_fingerprint')
    
    client_ip = get_client_ip(request)
    user_agent = request.META.get('HTTP_USER_AGENT', '')
    
    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile
        
        # Check if enrolled
        if not zk_user.is_enrolled:
            AuthenticationLog.objects.create(
                user=zk_user,
                username=username,
                status='failed',
                ip_address=client_ip,
                user_agent=user_agent,
                error_message='Utilisateur non enrôlé'
            )
            return Response({
                'success': False,
                'error': 'Utilisateur non enrôlé'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Check if account is locked
        if zk_user.is_locked():
            AuthenticationLog.objects.create(
                user=zk_user,
                username=username,
                status='locked',
                ip_address=client_ip,
                user_agent=user_agent,
                error_message='Compte verrouillé'
            )
            return Response({
                'success': False,
                'error': 'Compte temporairement verrouillé',
                'locked_until': zk_user.locked_until.isoformat()
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Verify challenge exists and is valid
        challenge_value = proof_data['challenge']
        
        try:
            challenge = AuthenticationChallenge.objects.get(
                user=zk_user,
                challenge=challenge_value
            )
            
            if not challenge.is_valid():
                zk_user.increment_failed_attempts()
                
                AuthenticationLog.objects.create(
                    user=zk_user,
                    username=username,
                    status='expired',
                    ip_address=client_ip,
                    user_agent=user_agent,
                    challenge_used=challenge_value,
                    error_message='Challenge expiré ou déjà utilisé'
                )
                
                return Response({
                    'success': False,
                    'error': 'Challenge expiré ou déjà utilisé'
                }, status=status.HTTP_400_BAD_REQUEST)
                
        except AuthenticationChallenge.DoesNotExist:
            zk_user.increment_failed_attempts()
            
            AuthenticationLog.objects.create(
                user=zk_user,
                username=username,
                status='failed',
                ip_address=client_ip,
                user_agent=user_agent,
                challenge_used=challenge_value,
                error_message='Challenge invalide'
            )
            
            return Response({
                'success': False,
                'error': 'Challenge invalide'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Verify Schnorr proof
        is_valid = verify_schnorr_proof(
            zk_user.public_key,
            proof_data,
            challenge_value
        )
        
        if is_valid:
            with transaction.atomic():
                # Mark challenge as used
                challenge.mark_as_used()
                
                # Reset failed attempts
                zk_user.reset_failed_attempts()
                zk_user.last_authentication = timezone.now()
                zk_user.save()
                
                # Create secure session token
                access_token = secrets.token_urlsafe(32)
                refresh_token = secrets.token_urlsafe(32)
                
                token_session = TokenSession.objects.create(
                    user=zk_user,
                    token=access_token,
                    refresh_token=refresh_token,
                    ip_address=client_ip,
                    user_agent=user_agent,
                    device_fingerprint=device_fingerprint,
                    expires_at=timezone.now() + timedelta(hours=24)
                )
                
                # Log successful authentication
                AuthenticationLog.objects.create(
                    user=zk_user,
                    username=username,
                    status='success',
                    ip_address=client_ip,
                    user_agent=user_agent,
                    challenge_used=challenge_value
                )
                
                logger.info(f"Authentication successful: {username}")
                
                return Response({
                    'success': True,
                    'message': 'Authentification réussie',
                    'access_token': access_token,
                    'refresh_token': refresh_token,
                    'expires_at': token_session.expires_at.isoformat(),
                    'user': ZKAuthUserSerializer(zk_user).data
                }, status=status.HTTP_200_OK)
        else:
            # Invalid proof
            zk_user.increment_failed_attempts()
            
            AuthenticationLog.objects.create(
                user=zk_user,
                username=username,
                status='failed',
                ip_address=client_ip,
                user_agent=user_agent,
                challenge_used=challenge_value,
                error_message='Preuve invalide'
            )
            
            logger.warning(f"Authentication failed: {username}")
            
            return Response({
                'success': False,
                'error': 'Authentification échouée'
            }, status=status.HTTP_401_UNAUTHORIZED)
            
    except User.DoesNotExist:
        AuthenticationLog.objects.create(
            username=username,
            status='failed',
            ip_address=client_ip,
            user_agent=user_agent,
            error_message='Utilisateur non trouvé'
        )
        
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé'
        }, status=status.HTTP_404_NOT_FOUND)
        
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        
        AuthenticationLog.objects.create(
            username=username,
            status='failed',
            ip_address=client_ip,
            user_agent=user_agent,
            error_message=str(e)
        )
        
        return Response({
            'success': False,
            'error': 'Erreur lors de l\'authentification'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def verify_token(request):
    """
    Verify if session token is still valid
    
    POST /api/auth/verify-token/
    Headers: Authorization: Bearer <token>
    """
    is_valid, token_session, error = verify_session_token(request)
    
    if not is_valid:
        return Response({
            'success': False,
            'error': error
        }, status=status.HTTP_401_UNAUTHORIZED)
    
    return Response({
        'success': True,
        'valid': True,
        'expires_at': token_session.expires_at.isoformat(),
        'user': ZKAuthUserSerializer(token_session.user).data
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
def refresh_token(request):
    """
    Refresh access token using refresh token
    
    POST /api/auth/refresh-token/
    {
        "refresh_token": "..."
    }
    """
    refresh_token = request.data.get('refresh_token')
    
    if not refresh_token:
        return Response({
            'success': False,
            'error': 'Refresh token requis'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        token_session = TokenSession.objects.get(refresh_token=refresh_token)
        
        if token_session.is_revoked:
            return Response({
                'success': False,
                'error': 'Session révoquée'
            }, status=status.HTTP_401_UNAUTHORIZED)
        
        # Generate new access token
        new_access_token = secrets.token_urlsafe(32)
        token_session.token = new_access_token
        token_session.expires_at = timezone.now() + timedelta(hours=24)
        token_session.save()
        
        return Response({
            'success': True,
            'access_token': new_access_token,
            'expires_at': token_session.expires_at.isoformat()
        }, status=status.HTTP_200_OK)
        
    except TokenSession.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Refresh token invalide'
        }, status=status.HTTP_401_UNAUTHORIZED)


@api_view(['POST'])
def logout(request):
    """
    Logout and revoke session
    
    POST /api/auth/logout/
    Headers: Authorization: Bearer <token>
    """
    is_valid, token_session, error = verify_session_token(request)
    
    if not is_valid:
        return Response({
            'success': False,
            'error': error
        }, status=status.HTTP_401_UNAUTHORIZED)
    
    # Revoke session
    token_session.revoke()
    
    logger.info(f"🔒 User logged out: {token_session.user.user.username}")
    
    return Response({
        'success': True,
        'message': 'Déconnexion réussie'
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
def revoke_enrollment(request):
    """
    Revoke user enrollment (for lost/stolen devices)
    
    POST /api/auth/revoke/
    {
        "username": "johndoe"
    }
    """
    username = request.data.get('username')
    
    if not username:
        return Response({
            'success': False,
            'error': 'Username requis'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile
        
        with transaction.atomic():
            # Revoke enrollment
            zk_user.public_key = None
            zk_user.is_enrolled = False
            zk_user.enrollment_status = 'revoked'
            zk_user.save()
            
            # Deactivate all devices
            zk_user.devices.update(is_active=False)
            
            # Invalidate all challenges
            zk_user.challenges.filter(used=False).update(used=True)
            
            # Revoke all active sessions
            zk_user.sessions.filter(is_revoked=False).update(
                is_revoked=True,
                revoked_at=timezone.now()
            )
            
            logger.info(f"🔒 Enrollment revoked: {username}")
            
            return Response({
                'success': True,
                'message': 'Enrôlement révoqué avec succès'
            }, status=status.HTTP_200_OK)
            
    except User.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Revocation error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur lors de la révocation'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def save_backup_fragment(request):
    """
    Save backup fragment B on server
    
    POST /api/auth/backup-fragment/
    {
        "username": "johndoe",
        "fragment": "encrypted_fragment_b",
        "fragment_type": "B"
    }
    """
    username = request.data.get('username')
    fragment = request.data.get('fragment')
    fragment_type = request.data.get('fragment_type', 'B')
    
    if not all([username, fragment]):
        return Response({
            'success': False,
            'error': 'Username et fragment requis'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        user = User.objects.get(username=username)
        zk_user = user.zk_auth_profile
        
        # Create or update backup
        backup, created = KeyBackup.objects.get_or_create(user=zk_user)
        backup.fragment_b_encrypted = fragment
        backup.save()
        
        logger.info(f"💾 Backup fragment saved for: {username}")
        
        return Response({
            'success': True,
            'message': 'Fragment sauvegardé'
        }, status=status.HTTP_201_CREATED if created else status.HTTP_200_OK)
        
    except User.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Backup save error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur sauvegarde fragment'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


@api_view(['POST'])
def restore_account(request):
    """
    Retrieve backup fragment B for account restoration
    
    POST /api/auth/restore-fragment/
    {
        "username": "johndoe",
        "email": "john@example.com"  # for verification
    }
    """
    username = request.data.get('username')
    email = request.data.get('email')
    
    if not all([username, email]):
        return Response({
            'success': False,
            'error': 'Username et email requis'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        user = User.objects.get(username=username, email=email)
        zk_user = user.zk_auth_profile
        
        try:
            backup = zk_user.key_backup
            
            if not backup.fragment_b_encrypted:
                return Response({
                    'success': False,
                    'error': 'Aucune sauvegarde trouvée'
                }, status=status.HTTP_404_NOT_FOUND)
            
            logger.info(f"🔄 Fragment retrieved for restoration: {username}")
            
            return Response({
                'success': True,
                'fragment_b': backup.fragment_b_encrypted,
                'created_at': backup.created_at.isoformat()
            }, status=status.HTTP_200_OK)
            
        except KeyBackup.DoesNotExist:
            return Response({
                'success': False,
                'error': 'Aucune sauvegarde trouvée'
            }, status=status.HTTP_404_NOT_FOUND)
        
    except User.DoesNotExist:
        return Response({
            'success': False,
            'error': 'Utilisateur non trouvé ou email incorrect'
        }, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        logger.error(f"Restore error: {str(e)}")
        return Response({
            'success': False,
            'error': 'Erreur restauration'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
