"""
Django admin configuration for ZK-AUTH models
"""
from django.contrib import admin
from .models import ZKAuthUser, AuthenticationChallenge, AuthenticationLog, DeviceInfo


@admin.register(ZKAuthUser)
class ZKAuthUserAdmin(admin.ModelAdmin):
    list_display = ['username',  'is_enrolled', 'enrolled_at', 'last_authentication']
    list_filter = ['is_enrolled', 'created_at']
    search_fields = ['user__username', ]
    readonly_fields = ['created_at', 'updated_at', 'enrolled_at']
    
    def username(self, obj):
        return obj.user.username
    username.short_description = 'Username'


@admin.register(AuthenticationChallenge)
class AuthenticationChallengeAdmin(admin.ModelAdmin):
    list_display = ['user', 'challenge_short', 'created_at', 'expires_at', 'used']
    list_filter = ['used', 'created_at']
    search_fields = ['user__user__username', 'challenge']
    readonly_fields = ['created_at', 'used_at']
    
    def challenge_short(self, obj):
        return f"{obj.challenge[:20]}..."
    challenge_short.short_description = 'Challenge'


@admin.register(AuthenticationLog)
class AuthenticationLogAdmin(admin.ModelAdmin):
    list_display = ['username', 'status', 'ip_address', 'timestamp']
    list_filter = ['status', 'timestamp']
    search_fields = ['username', 'ip_address']
    readonly_fields = ['timestamp']
    date_hierarchy = 'timestamp'


@admin.register(DeviceInfo)
class DeviceInfoAdmin(admin.ModelAdmin):
    list_display = ['user', 'device_name', 'device_type', 'is_active', 'last_used']
    list_filter = ['device_type', 'is_active', 'enrolled_at']
    search_fields = ['user__user__username', 'device_name', 'device_id']
    readonly_fields = ['enrolled_at', 'last_used']
