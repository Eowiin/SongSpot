from django.http import FileResponse
from django.http import Http404
from django.shortcuts import render
from pathlib import Path


def landing_page(request):
    return render(request, "site/index.html", {"active_page": "home"})


def privacy_page(request):
    return render(request, "site/privacy.html", {"active_page": "privacy"})


def support_page(request):
    return render(request, "site/support.html", {"active_page": "support"})


def terms_page(request):
    return render(request, "site/terms.html", {"active_page": "terms"})


def account_page(request):
    return render(request, "site/account.html", {"active_page": "account"})


def account_delete_page(request):
    return render(
        request,
        "site/account_delete.html",
        {"active_page": "account"},
    )


def account_export_page(request):
    return render(
        request,
        "site/account_export.html",
        {"active_page": "account"},
    )


def site_logo(request):
    logo_path = Path(__file__).resolve().parent / "static" / "site" / "songspot-logo.png"
    if not logo_path.exists():
        raise Http404("Logo file not found")
    return FileResponse(logo_path.open("rb"), content_type="image/png")
