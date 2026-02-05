"""
Serializers for ZK-AUTH API
"""
from rest_framework import serializers
from django.contrib.auth.models import User
from .models import ZKAuthUser, AuthenticationLog, DeviceInfo


class UserRegistrationSerializer(serializers.Serializer):
    """Serializer for user registration"""
    username = serializers.CharField(max_length=150)
    email = serializers.EmailField()
    phone = serializers.CharField(max_length=20)
    
    def validate_username(self, value):
        if User.objects.filter(username=value).exists():
            raise serializers.ValidationError("Ce nom d'utilisateur existe dÃ©jÃ ")
        return value
    
    def validate_email(self, value):
        if User.objects.filter(email=value).exists():
            raise serializers.ValidationError("Cet email est dÃ©jÃ  utilisÃ©")
        return value
    
    def validate_phone(self, value):
        if ZKAuthUser.objects.filter(phone=value).exists():
            raise serializers.ValidationError("Ce numÃ©ro de tÃ©lÃ©phone est dÃ©jÃ  utilisÃ©")
        return value


class EnrollmentSerializer(serializers.Serializer):
    """Serializer for ZK-AUTH enrollment"""
    username = serializers.CharField(max_length=150)
    public_key = serializers.CharField()
    device_id = serializers.CharField(required=False)
    device_name = serializers.CharField(required=False)
    device_type = serializers.CharField(required=False)
    
    def validate_public_key(self, value):
        """Validate public key format"""
        # Remove 04 prefix if present
        key = value[2:] if value.startswith('04') else value
        
        # Should be 128 hex characters (64 bytes)
        if len(key) != 128:
            raise serializers.ValidationError("ClÃ© publique invalide (longueur incorrecte)")
        
        # Should be valid hex
        try:
            int(key, 16)
        except ValueError:
            raise serializers.ValidationError("ClÃ© publique invalide (format hexadÃ©cimal requis)")
        
        return value


class ZKProofSerializer(serializers.Serializer):
    """Serializer for Zero-Knowledge proof"""
    r = serializers.CharField(help_text="Commitment (hex)")
    s = serializers.CharField(help_text="Response (hex)")
    challenge = serializers.CharField(help_text="Challenge (hex)")


class AuthenticationSerializer(serializers.Serializer):
    """Serializer for authentication request"""
    username = serializers.CharField(max_length=150)
    proof = ZKProofSerializer()


class ZKAuthUserSerializer(serializers.ModelSerializer):
    """Serializer for ZKAuthUser model"""
    username = serializers.CharField(source='user.username', read_only=True)
    email = serializers.EmailField(source='user.email', read_only=True)
    
    class Meta:
        model = ZKAuthUser
        fields = [
            'id',
            'username',
            'email',
            'phone',
            'is_enrolled',
            'enrolled_at',
            'last_authentication',
            'created_at',
        ]
        read_only_fields = fields


class AuthenticationLogSerializer(serializers.ModelSerializer):
    """Serializer for authentication logs"""
    username = serializers.CharField(read_only=True)
    
    class Meta:
        model = AuthenticationLog
        fields = [
            'id',
            'username',
            'status',
            'ip_address',
            'challenge_used',
            'error_message',
            'timestamp',
        ]
        read_only_fields = fields


class DeviceInfoSerializer(serializers.ModelSerializer):
    """Serializer for device information"""
    
    class Meta:
        model = DeviceInfo
        fields = [
            'id',
            'device_id',
            'device_name',
            'device_type',
            'device_model',
            'os_version',
            'app_version',
            'is_active',
            'last_used',
            'enrolled_at',
        ]
        read_only_fields = ['id', 'last_used', 'enrolled_at']
