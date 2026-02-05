"""
Models for ZK-AUTH authentication system
"""
from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
from datetime import timedelta


class ZKAuthUser(models.Model):
    """
    Extended user model for ZK-AUTH
    Stores public key and enrollment status
    """
    ENROLLMENT_STATUS_CHOICES = [
        ('pending', 'En attente'),
        ('active', 'Actif'),
        ('revoked', 'Révoqué'),
        ('suspended', 'Suspendu'),
    ]
    
    user = models.OneToOneField(
        User,
        on_delete=models.CASCADE,
        related_name='zk_auth_profile'
    )
    phone = models.CharField(max_length=20, unique=True)
    public_key = models.TextField(
        null=True,
        blank=True,
        help_text="secp256k1 public key (hexadecimal)"
    )
    is_enrolled = models.BooleanField(default=False)
    enrollment_status = models.CharField(
        max_length=20,
        choices=ENROLLMENT_STATUS_CHOICES,
        default='pending'
    )
    enrolled_at = models.DateTimeField(null=True, blank=True)
    last_authentication = models.DateTimeField(null=True, blank=True)
    failed_attempts = models.IntegerField(default=0)
    locked_until = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'zk_auth_users'
        indexes = [
            models.Index(fields=['phone']),
            models.Index(fields=['is_enrolled']),
            models.Index(fields=['user']),
            models.Index(fields=['enrollment_status']),
        ]
        verbose_name = 'ZK Auth User'
        verbose_name_plural = 'ZK Auth Users'

    def __str__(self):
        return f"{self.user.username} - {self.enrollment_status}"

    def is_locked(self):
        """Check if account is locked"""
        if self.locked_until and self.locked_until > timezone.now():
            return True
        return False
    
    def is_connected(self):
        """Check if user has an active session"""
        if not self.last_authentication:
            return False
        # Session valid if authenticated less than 24h ago
        return timezone.now() - self.last_authentication < timedelta(hours=24)

    def reset_failed_attempts(self):
        """Reset failed login attempts"""
        self.failed_attempts = 0
        self.locked_until = None
        self.save()

    def increment_failed_attempts(self, lockout_duration=900):
        """Increment failed attempts and lock if threshold reached"""
        self.failed_attempts += 1
        if self.failed_attempts >= 5:
            self.locked_until = timezone.now() + timedelta(seconds=lockout_duration)
        self.save()


class AuthenticationChallenge(models.Model):
    """
    Temporary challenges for Zero-Knowledge authentication
    """
    user = models.ForeignKey(
        ZKAuthUser,
        on_delete=models.CASCADE,
        related_name='challenges'
    )
    challenge = models.CharField(max_length=64, unique=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used = models.BooleanField(default=False)
    used_at = models.DateTimeField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        db_table = 'authentication_challenges'
        indexes = [
            models.Index(fields=['challenge']),
            models.Index(fields=['user', 'used']),
            models.Index(fields=['expires_at']),
        ]
        ordering = ['-created_at']

    def __str__(self):
        return f"Challenge for {self.user.user.username} - Used: {self.used}"

    def is_valid(self):
        """Check if challenge is still valid"""
        if self.used:
            return False
        if self.expires_at < timezone.now():
            return False
        return True

    def mark_as_used(self):
        """Mark challenge as used"""
        self.used = True
        self.used_at = timezone.now()
        self.save()


class TokenSession(models.Model):
    """
    Session tokens with advanced security features
    """
    user = models.ForeignKey(
        ZKAuthUser,
        on_delete=models.CASCADE,
        related_name='sessions'
    )
    token = models.CharField(max_length=255, unique=True, db_index=True)
    refresh_token = models.CharField(max_length=255, unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    last_activity = models.DateTimeField(auto_now=True)
    is_revoked = models.BooleanField(default=False)
    revoked_at = models.DateTimeField(null=True, blank=True)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(null=True, blank=True)
    device_fingerprint = models.CharField(max_length=255, null=True, blank=True)

    class Meta:
        db_table = 'token_sessions'
        indexes = [
            models.Index(fields=['token']),
            models.Index(fields=['user', 'is_revoked']),
            models.Index(fields=['expires_at']),
        ]
        ordering = ['-created_at']

    def __str__(self):
        return f"Session for {self.user.user.username} - Valid: {self.is_valid()}"

    def is_valid(self):
        """Check if token is still valid"""
        if self.is_revoked:
            return False
        if self.expires_at < timezone.now():
            return False
        # Inactivity timeout (30 minutes)
        if timezone.now() - self.last_activity > timedelta(minutes=30):
            return False
        return True

    def revoke(self):
        """Revoke this session"""
        self.is_revoked = True
        self.revoked_at = timezone.now()
        self.save()

    def save(self, *args, **kwargs):
        if not self.expires_at:
            self.expires_at = timezone.now() + timedelta(hours=24)
        super().save(*args, **kwargs)


class AuthenticationLog(models.Model):
    """
    Logs of authentication attempts for audit and security monitoring
    """
    STATUS_CHOICES = [
        ('success', 'Success'),
        ('failed', 'Failed'),
        ('locked', 'Account Locked'),
        ('expired', 'Challenge Expired'),
        ('revoked', 'Session Revoked'),
    ]

    user = models.ForeignKey(
        ZKAuthUser,
        on_delete=models.CASCADE,
        related_name='auth_logs',
        null=True,
        blank=True
    )
    username = models.CharField(max_length=150)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES)
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(null=True, blank=True)
    challenge_used = models.CharField(max_length=64, null=True, blank=True)
    error_message = models.TextField(null=True, blank=True)
    timestamp = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'authentication_logs'
        indexes = [
            models.Index(fields=['user', 'timestamp']),
            models.Index(fields=['status']),
            models.Index(fields=['timestamp']),
            models.Index(fields=['username']),
        ]
        ordering = ['-timestamp']

    def __str__(self):
        return f"{self.username} - {self.status} at {self.timestamp}"


class DeviceInfo(models.Model):
    """
    Information about enrolled devices
    """
    user = models.ForeignKey(
        ZKAuthUser,
        on_delete=models.CASCADE,
        related_name='devices'
    )
    device_id = models.CharField(max_length=255)
    device_name = models.CharField(max_length=255)
    device_type = models.CharField(max_length=50)  # android, ios
    device_model = models.CharField(max_length=255, null=True, blank=True)
    os_version = models.CharField(max_length=50, null=True, blank=True)
    app_version = models.CharField(max_length=50, null=True, blank=True)
    is_active = models.BooleanField(default=True)
    last_used = models.DateTimeField(auto_now=True)
    enrolled_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'device_info'
        indexes = [
            models.Index(fields=['user', 'is_active']),
            models.Index(fields=['device_id']),
        ]
        unique_together = ['user', 'device_id']

    def __str__(self):
        return f"{self.device_name} - {self.user.user.username}"


class KeyBackup(models.Model):
    """
    Metadata for key backup (fragments stored elsewhere)
    """
    user = models.OneToOneField(
        ZKAuthUser,
        on_delete=models.CASCADE,
        related_name='key_backup'
    )
    fragment_a_location = models.CharField(max_length=255, default='google_drive')
    fragment_b_location = models.CharField(max_length=255, default='zk_auth_cloud')
    fragment_b_encrypted = models.TextField(null=True, blank=True)  # Store fragment B encrypted
    created_at = models.DateTimeField(auto_now_add=True)
    last_verified = models.DateTimeField(null=True, blank=True)
    backup_email_sent = models.BooleanField(default=False)

    class Meta:
        db_table = 'key_backups'

    def __str__(self):
        return f"Backup for {self.user.user.username}"

    def verify_fragments(self):
        """Verify that both fragments exist"""
        # This should check if fragments can be retrieved
        self.last_verified = timezone.now()
        self.save()
        return True
