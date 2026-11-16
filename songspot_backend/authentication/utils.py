def normalize_locale(raw_locale: str | None) -> str:
    value = (raw_locale or '').strip().lower()
    return 'fr' if value.startswith('fr') else 'en'
