#!/usr/bin/env python3
"""Validate backend/frontend error-code sync for SongSpot."""

from __future__ import annotations

import ast
import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BACKEND_ERROR_FILE = ROOT / "songspot_backend" / "songspot" / "api_errors.py"
FRONTEND_API_FILE = ROOT / "songspot_mobile" / "lib" / "services" / "api_service.dart"
L10N_DIR = ROOT / "songspot_mobile" / "lib" / "l10n"


def parse_backend_error_codes(path: Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    tree = ast.parse(source, filename=str(path))

    codes: set[str] = set()
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and node.name == "ErrorCode":
            for item in node.body:
                if (
                    isinstance(item, ast.Assign)
                    and len(item.targets) == 1
                    and isinstance(item.targets[0], ast.Name)
                    and isinstance(item.value, ast.Constant)
                    and isinstance(item.value.value, str)
                ):
                    value = item.value.value.strip()
                    if value:
                        codes.add(value)
            break

    if not codes:
        raise RuntimeError(f"No ErrorCode values found in {path}")

    return codes


def parse_frontend_error_cases(path: Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    # Matches: case 'ROOM_LIMIT_REACHED':
    return set(re.findall(r"case\s+'([A-Z0-9_]+)'\s*:", source))


def parse_frontend_backend_l10n_keys(path: Path) -> set[str]:
    source = path.read_text(encoding="utf-8")
    # Matches backend localization members used on AppLocalizations:
    # l10n.backendFoo or l10n.backendFoo(...)
    return set(re.findall(r"l10n\.(backend[A-Za-z0-9_]+)\b", source))


def parse_arb_keys(path: Path) -> set[str]:
    data = json.loads(path.read_text(encoding="utf-8"))
    # Ignore metadata keys like @@locale and @someKey docs
    return {k for k in data.keys() if not k.startswith("@")}


def parse_arb_locale(path: Path) -> str:
    data = json.loads(path.read_text(encoding="utf-8"))
    locale = data.get("@@locale")
    if isinstance(locale, str) and locale.strip():
        return locale.strip()

    # Fallback to filename if @@locale is missing.
    match = re.fullmatch(r"app_(.+)\.arb", path.name)
    if match:
        return match.group(1)
    return path.stem


def discover_arb_files(path: Path) -> dict[str, Path]:
    locale_files: dict[str, Path] = {}
    for arb_file in sorted(path.glob("app_*.arb")):
        locale = parse_arb_locale(arb_file)
        locale_files[locale] = arb_file
    return locale_files


def fail(message: str) -> None:
    print(message, file=sys.stderr)


def main() -> int:
    required_files = [
        BACKEND_ERROR_FILE,
        FRONTEND_API_FILE,
        L10N_DIR,
    ]
    missing_files = [str(p) for p in required_files if not p.exists()]
    if missing_files:
        fail("Missing required files:")
        for path in missing_files:
            fail(f"  - {path}")
        return 1

    arb_files = discover_arb_files(L10N_DIR)
    if not arb_files:
        fail(f"No app_*.arb locale files found in {L10N_DIR}")
        return 1

    backend_codes = parse_backend_error_codes(BACKEND_ERROR_FILE)
    frontend_cases = parse_frontend_error_cases(FRONTEND_API_FILE)

    missing_frontend_cases = sorted(backend_codes - frontend_cases)
    stale_frontend_cases = sorted(frontend_cases - backend_codes)

    backend_l10n_keys_used = parse_frontend_backend_l10n_keys(FRONTEND_API_FILE)
    locale_keys = {locale: parse_arb_keys(path) for locale, path in arb_files.items()}

    # Prefer en as the reference locale; otherwise pick first locale alphabetically.
    reference_locale = "en" if "en" in locale_keys else sorted(locale_keys.keys())[0]
    reference_backend_keys = {
        key for key in locale_keys[reference_locale] if key.startswith("backend")
    }

    missing_in_locale: dict[str, list[str]] = {}
    backend_key_mismatch: dict[str, list[str]] = {}
    for locale, keys in sorted(locale_keys.items()):
        missing = sorted(backend_l10n_keys_used - keys)
        if missing:
            missing_in_locale[locale] = missing

        mismatched = sorted(reference_backend_keys ^ {k for k in keys if k.startswith("backend")})
        if mismatched:
            backend_key_mismatch[locale] = mismatched

    has_errors = False

    if missing_frontend_cases:
        has_errors = True
        fail("Backend ErrorCode values missing in frontend _localizeBackendCode switch:")
        for code in missing_frontend_cases:
            fail(f"  - {code}")

    if stale_frontend_cases:
        has_errors = True
        fail("Frontend _localizeBackendCode has cases not defined in backend ErrorCode:")
        for code in stale_frontend_cases:
            fail(f"  - {code}")

    if missing_in_locale:
        has_errors = True
        fail("Backend l10n keys used in api_service.dart are missing in locale files:")
        for locale, keys in sorted(missing_in_locale.items()):
            fail(f"  [{locale}]")
            for key in keys:
                fail(f"    - {key}")

    if backend_key_mismatch:
        has_errors = True
        fail(
            f"Backend key set mismatch across locales (reference: {reference_locale}). "
            "All locales should contain the same backend* keys:"
        )
        for locale, keys in sorted(backend_key_mismatch.items()):
            if locale == reference_locale:
                continue
            fail(f"  [{locale}]")
            for key in keys:
                fail(f"    - {key}")

    if has_errors:
        return 1

    print("Error-code sync check passed.")
    print(f"Backend codes: {len(backend_codes)}")
    print(f"Frontend switch cases: {len(frontend_cases)}")
    print(f"Backend l10n keys validated: {len(backend_l10n_keys_used)}")
    print(f"Locales checked: {len(locale_keys)} ({', '.join(sorted(locale_keys.keys()))})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
