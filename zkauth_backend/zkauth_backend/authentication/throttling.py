"""
Rate Limiting pour ZK-AUTH API - NOUVEAU FICHIER
Correction audit 4.2.3 : Ajout de rate limiting DRF

Protections :
  - Register : 10 requetes/min (anonyme)
  - Authenticate : 5 requetes/min (anonyme) - protection brute force
  - Challenge : 10 requetes/min (anonyme)
  - Sensitive operations : 3 requetes/min (revocation, restauration)
"""
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class RegisterRateThrottle(AnonRateThrottle):
    """Limite les tentatives d'inscription a 10/min"""
    rate = '10/min'
    scope = 'register'


class AuthenticateRateThrottle(AnonRateThrottle):
    """Limite les tentatives d'authentification a 5/min"""
    rate = '5/min'
    scope = 'authenticate'


class ChallengeRateThrottle(AnonRateThrottle):
    """Limite les demandes de challenge a 10/min"""
    rate = '10/min'
    scope = 'challenge'


class SensitiveOperationThrottle(AnonRateThrottle):
    """Limite les operations sensibles (revocation, restauration) a 3/min"""
    rate = '3/min'
    scope = 'sensitive'


class AuthenticatedUserThrottle(UserRateThrottle):
    """Limite pour les utilisateurs authentifies a 30/min"""
    rate = '30/min'
    scope = 'authenticated'
