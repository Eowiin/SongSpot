import logging

from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.db import IntegrityError, transaction
from django.utils import timezone

from .models import CoinProduct, IAPReceipt
from .iap_service import verify_apple_receipt, verify_google_receipt

logger = logging.getLogger(__name__)


class CoinProductListView(APIView):
    """
    List all active coin packs available for purchase.

    GET /api/auth/coin-products/
    Headers: Authorization: Bearer <access_token>

    Returns a list of coin products with their store product IDs,
    coin amounts, display prices, and bonus labels.
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        products = CoinProduct.objects.filter(is_active=True)
        data = [
            {
                'id': str(p.id),
                'product_id': p.product_id,
                'name': p.name,
                'coins_amount': p.coins_amount,
                'price_display': p.price_display,
                'bonus_label': p.bonus_label,
                'sort_order': p.sort_order,
            }
            for p in products
        ]
        return Response(data, status=status.HTTP_200_OK)


class IAPVerifyView(APIView):
    """
    Verify an in-app purchase receipt and credit coins.

    POST /api/auth/iap/verify/
    Headers: Authorization: Bearer <access_token>
    Body: {
        "store": "apple" | "google",
        "product_id": "com.songspot.coins.500",
        "transaction_id": "store-assigned-transaction-id",
        "receipt_data": "raw-receipt-or-token"
    }

    Flow:
    1. Check transaction_id not already processed (idempotency)
    2. Look up CoinProduct by product_id
    3. Verify receipt with Apple/Google servers
    4. Create IAPReceipt audit record
    5. Credit coins atomically
    """
    permission_classes = [IsAuthenticated]

    def post(self, request):
        store = request.data.get('store', '').strip().lower()
        product_id = request.data.get('product_id', '').strip()
        transaction_id = request.data.get('transaction_id', '').strip()
        receipt_data = request.data.get('receipt_data', '').strip()

        # Validate required fields
        if not all([store, product_id, transaction_id, receipt_data]):
            return Response(
                {'error': 'Missing required fields: store, product_id, transaction_id, receipt_data'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if store not in ('apple', 'google'):
            return Response(
                {'error': 'Invalid store. Must be "apple" or "google".'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Idempotency: check if this transaction was already processed
        existing = IAPReceipt.objects.filter(transaction_id=transaction_id).first()
        if existing:
            if existing.status == IAPReceipt.STATUS_VERIFIED:
                return Response({
                    'message': 'Purchase already verified',
                    'coins': request.user.coins,
                    'coins_credited': existing.coins_credited,
                }, status=status.HTTP_200_OK)
            elif existing.status == IAPReceipt.STATUS_PENDING:
                return Response(
                    {'error': 'Purchase is still being processed. Please wait.'},
                    status=status.HTTP_409_CONFLICT,
                )

        # Look up the coin product
        try:
            coin_product = CoinProduct.objects.get(product_id=product_id, is_active=True)
        except CoinProduct.DoesNotExist:
            return Response(
                {'error': f'Unknown or inactive product: {product_id}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Create pending receipt record.
        # Use try/except to handle the race condition where two requests arrive
        # simultaneously and both pass the idempotency filter above.
        try:
            iap_receipt = IAPReceipt.objects.create(
                user=request.user,
                coin_product=coin_product,
                store=store,
                transaction_id=transaction_id,
                receipt_data=receipt_data,
                status=IAPReceipt.STATUS_PENDING,
            )
        except IntegrityError:
            # Another concurrent request already created this receipt.
            existing = IAPReceipt.objects.filter(transaction_id=transaction_id).first()
            if existing and existing.status == IAPReceipt.STATUS_VERIFIED:
                return Response({
                    'message': 'Purchase already verified',
                    'coins': request.user.coins,
                    'coins_credited': existing.coins_credited,
                }, status=status.HTTP_200_OK)
            return Response(
                {'error': 'Purchase is being processed. Please wait a moment.'},
                status=status.HTTP_409_CONFLICT,
            )

        # Verify with the appropriate store
        if store == 'apple':
            result = verify_apple_receipt(transaction_id, receipt_data)
        else:
            result = verify_google_receipt(transaction_id, receipt_data, product_id)

        if not result.get('valid'):
            iap_receipt.status = IAPReceipt.STATUS_FAILED
            iap_receipt.error_message = result.get('error', 'Verification failed')
            iap_receipt.save(update_fields=['status', 'error_message'])
            logger.warning(
                "IAP verification failed for user %s, transaction %s: %s",
                request.user.id, transaction_id, result.get('error')
            )
            return Response(
                {'error': 'Receipt verification failed. Please contact support if you were charged.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Credit coins atomically
        with transaction.atomic():
            coins_amount = coin_product.coins_amount
            request.user.add_coins(
                coins_amount,
                reason=f"IAP: {coin_product.name} ({coin_product.product_id})",
                transaction_type='purchase',
            )
            iap_receipt.status = IAPReceipt.STATUS_VERIFIED
            iap_receipt.coins_credited = coins_amount
            iap_receipt.verified_at = timezone.now()
            iap_receipt.save(update_fields=['status', 'coins_credited', 'verified_at'])

        logger.info(
            "IAP verified: user %s credited %d coins for %s (transaction %s)",
            request.user.id, coins_amount, product_id, transaction_id
        )

        return Response({
            'message': 'Purchase verified successfully',
            'coins': request.user.coins,
            'coins_credited': coins_amount,
        }, status=status.HTTP_200_OK)
