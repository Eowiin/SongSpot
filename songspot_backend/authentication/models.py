import uuid
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone

class CustomUserManager(BaseUserManager):
    def create_user(self, username, email, password=None, **extra_fields):
        if not email:
            raise ValueError('The Email field must be set')
        email = self.normalize_email(email)
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

class User(AbstractBaseUser, PermissionsMixin):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    username = models.CharField(max_length=150)
    email = models.EmailField(unique=True)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    # Coin system
    coins = models.PositiveIntegerField(default=100, help_text="In-app currency for purchasing packs")

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

    def __str__(self):
        return self.email

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

    def add_coins(self, amount, reason=""):
        """Add coins to user's balance."""
        self.coins += amount
        self.save(update_fields=['coins'])
        # Log the transaction
        CoinTransaction.objects.create(
            user=self,
            amount=amount,
            transaction_type='earn',
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
