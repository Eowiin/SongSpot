def normalize_locale(raw_locale):
    value = (raw_locale or '').strip().lower()
    return 'fr' if value.startswith('fr') else 'en'
