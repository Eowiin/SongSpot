import uuid
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.db.models.functions import Lower
from django.utils import timezone

class CustomUserManager(BaseUserManager):
    def normalize_full_email(self, email):
        return self.model.normalize_email_value(email)

    def create_user(self, username, email, password=None, **extra_fields):
        if not email:
            raise ValueError('The Email field must be set')
        email = self.normalize_full_email(email)
        user = self.model(username=username, email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, username, email, password=None, **extra_fields):
        extra_fields.setdefault('is_staff', True)
        extra_fields.setdefault('is_superuser', True)

        if extra_fields.get('is_staff') is not True:
            raise ValueError('Superuser must have is_staff=True.')
        if extra_fields.get('is_superuser') is not True:
            raise ValueError('Superuser must have is_superuser=True.')

        return self.create_user(username, email, password, **extra_fields)

    def get_by_natural_key(self, username):
        return self.get(
            **{self.model.USERNAME_FIELD: self.normalize_full_email(username)}
        )

class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = models.CharField(max_length=150)
    email = models.EmailField(unique=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    # Coin system
    coins = models.PositiveIntegerField(default=100, help_text="In-app currency for purchasing packs")
    ad_free_until = models.DateTimeField(
        null=True,
        blank=True,
        help_text="When set in the future, ads are disabled for this user"
    )

    # Statistics
    games_played = models.PositiveIntegerField(default=0)
    games_won = models.PositiveIntegerField(default=0, help_text="Games where user guessed correctly")
    total_points = models.PositiveIntegerField(default=0)
    current_streak = models.PositiveIntegerField(default=0, help_text="Consecutive days with correct guesses")
    best_streak = models.PositiveIntegerField(default=0, help_text="Longest streak ever achieved")
    last_played_date = models.DateField(null=True, blank=True, help_text="Last date user completed a game")
    perfect_games = models.PositiveIntegerField(default=0, help_text="Games won on first snippet (6 points)")

    created_at = models.DateTimeField(default=timezone.now)

    objects = CustomUserManager()

    USERNAME_FIELD = 'email'
    REQUIRED_FIELDS = ['username']

    class Meta:
        constraints = [
            models.UniqueConstraint(
                Lower('email'),
                name='user_email_lower_unique',
            ),
        ]

    @staticmethod
    def normalize_email_value(email):
        if not isinstance(email, str):
            return email
        return email.strip().lower()

    def __str__(self):
        return self.email

    def save(self, *args, **kwargs):
        self.email = self.normalize_email_value(self.email)
        super().save(*args, **kwargs)

    @property
    def win_rate(self):
        """Calculate win percentage."""
        if self.games_played == 0:
            return 0.0
        return round((self.games_won / self.games_played) * 100, 1)

    @property
    def average_points(self):
        """Calculate average points per game."""
        if self.games_played == 0:
            return 0.0
        return round(self.total_points / self.games_played, 1)

    @property
    def has_no_ads(self):
        """Whether the user currently has an active ad-free pass."""
        return bool(self.ad_free_until and self.ad_free_until > timezone.now())

    def add_coins(self, amount, reason="", transaction_type='earn'):
        """Add coins to user's balance."""
        self.coins += amount
        self.save(update_fields=['coins'])
        # Log the transaction
        CoinTransaction.objects.create(
            user=self,
            amount=amount,
            transaction_type=transaction_type,
            reason=reason
        )
        return self.coins

    def spend_coins(self, amount, reason=""):
        """Spend coins from user's balance. Returns True if successful."""
        if self.coins < amount:
            return False
        self.coins -= amount
        self.save(update_fields=['coins'])
        # Log the transaction
        CoinTransaction.objects.create(
            user=self,
            amount=-amount,
            transaction_type='spend',
            reason=reason
        )
        return True

    def update_streak(self, won_today, played_date):
        """Update streak based on game result."""
        if self.last_played_date:
            days_since_last = (played_date - self.last_played_date).days

            if days_since_last == 1:
                # Consecutive day
                if won_today:
                    self.current_streak += 1
                else:
                    self.current_streak = 0
            elif days_since_last > 1:
                # Streak broken (missed days)
                self.current_streak = 1 if won_today else 0
            # days_since_last == 0 means same day, don't update streak
        else:
            # First game ever
            self.current_streak = 1 if won_today else 0

        # Update best streak if current is higher
        if self.current_streak > self.best_streak:
            self.best_streak = self.current_streak

        self.last_played_date = played_date
        self.save(update_fields=['current_streak', 'best_streak', 'last_played_date'])


class UserDevicePushToken(models.Model):
    """
    Stores one FCM token per mobile installation/device.
    A user can have multiple active devices at the same time.
    """

    PLATFORM_IOS = 'ios'
    PLATFORM_ANDROID = 'android'
    PLATFORM_CHOICES = [
        (PLATFORM_IOS, 'iOS'),
        (PLATFORM_ANDROID, 'Android'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='push_devices'
    )
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=20, choices=PLATFORM_CHOICES)
    device_id = models.CharField(max_length=191, blank=True, null=True)
    device_name = models.CharField(max_length=120, blank=True)
    app_version = models.CharField(max_length=50, blank=True)
    is_active = models.BooleanField(default=True)
    daily_song_enabled = models.BooleanField(default=True)
    messages_enabled = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(default=timezone.now)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'user_device_push_tokens'
        ordering = ['-last_seen_at']
        indexes = [
            models.Index(fields=['user', 'is_active'], name='udpt_user_active_idx'),
            models.Index(fields=['platform', 'is_active'], name='udpt_platform_active_idx'),
            models.Index(fields=['device_id'], name='udpt_device_id_idx'),
        ]

    def __str__(self):
        return f"{self.user.username} ({self.platform})"


class CoinTransaction(models.Model):
    """
    Tracks all coin transactions for auditing and history.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='coin_transactions'
    )
    amount = models.IntegerField(help_text="Positive for earn, negative for spend")
    transaction_type = models.CharField(
        max_length=20,
        choices=[
            ('earn', 'Earned'),
            ('spend', 'Spent'),
            ('bonus', 'Bonus'),
            ('refund', 'Refund'),
            ('purchase', 'IAP Purchase'),
        ]
    )
    reason = models.CharField(max_length=255, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'coin_transactions'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
        ]

    def __str__(self):
        sign = '+' if self.amount > 0 else ''
        return f"{self.user.username}: {sign}{self.amount} coins ({self.reason})"


class CoinProduct(models.Model):
    """
    Defines a coin pack available for real-money purchase via IAP.
    Product IDs must match App Store Connect / Google Play Console products.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    product_id = models.CharField(
        max_length=255,
        unique=True,
        help_text="Store product ID, e.g. 'com.songspot.coins.500'"
    )
    name = models.CharField(max_length=100)
    coins_amount = models.PositiveIntegerField(help_text="Number of coins awarded on purchase")
    price_display = models.CharField(
        max_length=20,
        blank=True,
        help_text="Reference display price, e.g. '$1.99'. Real price comes from the store."
    )
    bonus_label = models.CharField(
        max_length=50,
        blank=True,
        help_text="Optional badge label, e.g. 'Best Value!', 'Most Popular'"
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'coin_products'
        ordering = ['sort_order']

    def __str__(self):
        return f"{self.name} ({self.coins_amount} coins) - {self.product_id}"


class IAPReceipt(models.Model):
    """
    Audit log of every in-app purchase receipt verification attempt.
    Ensures idempotency via unique transaction_id.
    """
    STORE_APPLE = 'apple'
    STORE_GOOGLE = 'google'
    STORE_CHOICES = [
        (STORE_APPLE, 'Apple'),
        (STORE_GOOGLE, 'Google'),
    ]

    STATUS_PENDING = 'pending'
    STATUS_VERIFIED = 'verified'
    STATUS_FAILED = 'failed'
    STATUS_REFUNDED = 'refunded'
    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_VERIFIED, 'Verified'),
        (STATUS_FAILED, 'Failed'),
        (STATUS_REFUNDED, 'Refunded'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='iap_receipts'
    )
    coin_product = models.ForeignKey(
        CoinProduct,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='receipts'
    )
    store = models.CharField(max_length=10, choices=STORE_CHOICES)
    transaction_id = models.CharField(
        max_length=255,
        unique=True,
        help_text="Store-assigned transaction/order ID for idempotency"
    )
    receipt_data = models.TextField(
        blank=True,
        help_text="Raw receipt/token sent by the client for server verification"
    )
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    coins_credited = models.PositiveIntegerField(default=0)
    error_message = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    verified_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'iap_receipts'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['transaction_id']),
        ]

    def __str__(self):
        return f"{self.user.username} - {self.store} - {self.status} ({self.coins_credited} coins)"


class AdRewardClaim(models.Model):
    """
    Audit log for rewarded-ad coin grants.
    """
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        User,
        on_delete=models.CASCADE,
        related_name='ad_reward_claims',
    )
    placement = models.CharField(
        max_length=50,
        default='game_result',
        help_text="Where the rewarded ad was watched (e.g. game_result)"
    )
    coins_awarded = models.PositiveSmallIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'ad_reward_claims'
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['user', '-created_at']),
        ]

    def __str__(self):
        return f"{self.user.username}: +{self.coins_awarded} ({self.placement})"
