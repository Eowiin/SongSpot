"""
In-App Purchase receipt verification for Apple App Store and Google Play.

Apple: Uses App Store Server API v2 (JWS signed transactions).
Google: Uses Google Play Developer API via service account.
"""
import logging

from django.conf import settings

logger = logging.getLogger(__name__)


def verify_apple_receipt(transaction_id, receipt_data):
    """
    Verify an Apple App Store purchase.

    For production, this should validate the JWS (JSON Web Signature)
    signed transaction using Apple's root certificate, or call the
    App Store Server API v2 endpoint:
      GET https://api.storekit.itunes.apple.com/inApps/v1/transactions/{transactionId}

    Args:
        transaction_id: The store-assigned transaction ID.
        receipt_data: The signed transaction JWS string from StoreKit 2.

    Returns:
        dict with 'valid' (bool) and optional 'error' (str).
    """
    # TODO: Implement production Apple receipt verification.
    # For now, in sandbox/development mode, we trust the receipt.
    # In production you MUST validate the JWS signature.
    #
    # Steps for production:
    # 1. Decode the JWS header to get the x5c certificate chain
    # 2. Verify the certificate chain against Apple's root CA
    # 3. Verify the JWS signature
    # 4. Decode the payload and check transactionId, productId, environment
    #
    # Alternatively, use the App Store Server API:
    # - Generate a JWT using your App Store Connect API key
    # - GET /inApps/v1/transactions/{transactionId}
    # - Verify the response status

    if not receipt_data:
        return {'valid': False, 'error': 'Empty receipt data'}

    sandbox = getattr(settings, 'IAP_SANDBOX_MODE', True)
    if sandbox:
        logger.info("Apple IAP sandbox mode: accepting receipt for transaction %s", transaction_id)
        return {'valid': True}

    # Production verification placeholder
    logger.warning("Apple IAP production verification not yet implemented for transaction %s", transaction_id)
    return {'valid': False, 'error': 'Production Apple verification not yet implemented'}


def verify_google_receipt(transaction_id, receipt_data, product_id):
    """
    Verify a Google Play purchase.

    Uses the Google Play Developer API:
      purchases.products.get(packageName, productId, token)

    Args:
        transaction_id: The Google Play order ID.
        receipt_data: The purchase token from Google Play Billing.
        product_id: The product ID (e.g. 'com.songspot.coins.500').

    Returns:
        dict with 'valid' (bool) and optional 'error' (str).
    """
    # TODO: Implement production Google Play receipt verification.
    # For now, in sandbox/development mode, we trust the receipt.
    #
    # Steps for production:
    # 1. Set up a Google Cloud service account with androidpublisher scope
    # 2. Use google-api-python-client to call:
    #    androidpublisher.purchases.products.get(
    #        packageName='com.songspot.app',
    #        productId=product_id,
    #        token=receipt_data
    #    )
    # 3. Check purchaseState == 0 (purchased)
    # 4. Acknowledge the purchase if not yet acknowledged

    if not receipt_data:
        return {'valid': False, 'error': 'Empty receipt data'}

    sandbox = getattr(settings, 'IAP_SANDBOX_MODE', True)
    if sandbox:
        logger.info("Google IAP sandbox mode: accepting receipt for transaction %s", transaction_id)
        return {'valid': True}

    # Production verification placeholder
    logger.warning("Google IAP production verification not yet implemented for transaction %s", transaction_id)
    return {'valid': False, 'error': 'Production Google verification not yet implemented'}
