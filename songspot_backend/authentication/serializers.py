from rest_framework import serializers
from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from .models import UserDevicePushToken

User = get_user_model()

class UserRegistrationSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, required=True, validators=[validate_password])
    password_confirm = serializers.CharField(write_only=True, required=True)

    class Meta:
        model = User
        fields = ('email', 'username', 'password', 'password_confirm')

    def validate(self, attrs):
        if attrs['password'] != attrs['password_confirm']:
            raise serializers.ValidationError({"password": "Password fields didn't match."})
        return attrs

    def create(self, validated_data):
        validated_data.pop('password_confirm')
        user = User.objects.create_user(
            email=validated_data['email'],
            username=validated_data['username'],
            password=validated_data['password']
        )
        return user

class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ('id', 'email', 'username', 'coins')
        read_only_fields = ('id', 'coins')

class UserProfileSerializer(serializers.ModelSerializer):
    win_rate = serializers.FloatField(read_only=True)
    average_points = serializers.FloatField(read_only=True)

    class Meta:
        model = User
        fields = (
            'id', 'email', 'username', 'coins',
            'games_played', 'games_won', 'win_rate',
            'total_points', 'average_points',
            'current_streak', 'best_streak',
            'last_played_date', 'perfect_games'
        )
        read_only_fields = (
            'id', 'email', 'username', 'coins',
            'games_played', 'games_won', 'win_rate',
            'total_points', 'average_points',
            'current_streak', 'best_streak',
            'last_played_date', 'perfect_games'
        )

class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField(required=True)
    password = serializers.CharField(required=True, write_only=True)


class PushDeviceRegisterSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserDevicePushToken
        fields = (
            'token',
            'platform',
            'device_id',
            'device_name',
            'app_version',
            'daily_song_enabled',
            'messages_enabled',
        )
        extra_kwargs = {
            'token': {'validators': []},  # Remove UniqueValidator; view handles upsert
        }

    def validate_token(self, value):
        value = value.strip()
        if len(value) < 32:
            raise serializers.ValidationError('Invalid FCM token.')
        return value


class PushDeviceUnregisterSerializer(serializers.Serializer):
    token = serializers.CharField(required=True)

    def validate_token(self, value):
        value = value.strip()
        if not value:
            raise serializers.ValidationError('Token is required.')
        return value
