from django.conf import settings
from django.http import HttpResponse


def app_ads_txt(request):
    content = settings.APP_ADS_TXT.strip()
    if not content:
        return HttpResponse("", content_type="text/plain; charset=utf-8")
    return HttpResponse(f"{content}\n", content_type="text/plain; charset=utf-8")
