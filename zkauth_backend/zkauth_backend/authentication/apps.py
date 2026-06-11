"""
Authentication app configuration
"""
from django.apps import AppConfig


class AuthenticationConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'authentication'
    verbose_name = 'ZK-AUTH Authentication'
    
    def ready(self):
        # Import signals if any
        pass
