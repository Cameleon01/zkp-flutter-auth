"""
URL configuration for zkauth_project - CORRECTED
"""
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    # Inclure les URLs de l'app authentication
    path('', include('authentication.urls')),
]
