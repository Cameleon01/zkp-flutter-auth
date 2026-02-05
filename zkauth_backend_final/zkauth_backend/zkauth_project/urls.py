"""
URL configuration for authentication app
"""
from django.urls import path
from authentication import views
from authentication import urls

app_name = 'authentication'

urlpatterns = [
    # User management
    path('api/auth/register/', views.register_user, name='register'),
    path('api/auth/enroll/', views.enroll_user, name='enroll'),
    path('api/auth/revoke/', views.revoke_enrollment, name='revoke'),
    
    # Authentication
    path('api/auth/challenge/', views.get_challenge, name='challenge'),
    path('api/auth/authenticate/', views.authenticate_user, name='authenticate'),

    
    # Session management (NEW)
    path('api/auth/api/auth/verify-token/', views.verify_token, name='verify_token'),
    path('api/auth/refresh-token/', views.refresh_token, name='refresh_token'),
    path('api/auth/logout/', views.logout, name='logout'),
    
    # Backup & Restore (NEW)
    path('api/auth/backup-fragment/', views.save_backup_fragment, name='backup_fragment'),
    path('api/auth/restore-fragment/', views.restore_account, name='restore_fragment'),
]
