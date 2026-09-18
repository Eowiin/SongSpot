import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:songspot_mobile/l10n/app_localizations.dart';

/// Guards the .arb files against the two ways a translation rots: a key added
/// to the template and forgotten everywhere else, and a value pasted over from
/// English and never translated.
///
/// The generator is happy with both — a missing key silently falls back to
/// English at runtime — so nothing else catches them.
Map<String, String> _strings(String locale) {
  final raw = File('lib/l10n/app_$locale.arb').readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;
  return {
    for (final entry in json.entries)
      if (!entry.key.startsWith('@')) entry.key: entry.value as String,
  };
}

/// What a whole {name} placeholder or an ICU argument looks like. A bare '{'
/// would also match the '{1-second snippet}' of a plural branch, which is
/// text.
final _placeholder =
    RegExp(r'\{(\w+)(?:\}|\s*,\s*(?:plural|select|date|time)\b)');

Set<String> _placeholdersIn(String value) =>
    _placeholder.allMatches(value).map((m) => m.group(1)!).toSet();

void main() {
  final template = _strings('en');
  final translations = {
    for (final locale in AppLocalizations.supportedLocales)
      if (locale.languageCode != 'en') locale.languageCode: locale.languageCode,
  }.keys;

  test('every supported locale has an .arb file', () {
    for (final code in [
      for (final l in AppLocalizations.supportedLocales) l.languageCode
    ]) {
      expect(File('lib/l10n/app_$code.arb').existsSync(), isTrue,
          reason: 'lib/l10n/app_$code.arb is missing');
    }
  });

  for (final code in translations) {
    group(code, () {
      late Map<String, String> strings;
      setUp(() => strings = _strings(code));

      test('translates every key of the template', () {
        expect(strings.keys.toSet().difference(template.keys.toSet()), isEmpty,
            reason: 'keys that no longer exist in app_en.arb');
        expect(template.keys.toSet().difference(strings.keys.toSet()), isEmpty,
            reason: 'untranslated keys fall back to English at runtime');
      });

      test('keeps every placeholder', () {
        for (final key in template.keys) {
          final value = strings[key];
          if (value == null) continue;
          expect(_placeholdersIn(value), _placeholdersIn(template[key]!),
              reason: '$key: a dropped or renamed placeholder throws at build');
        }
      });

      test('is not a copy of the English', () {
        // Words that are genuinely the same in every language we ship, or
        // loanwords the French deliberately keeps ("round", not "manche").
        const shared = {
          'appTitle', 'emailLabel', 'duelVs', 'duelPts', 'dailyModeMixLabel',
          'dailyModeHardcoreLabel', 'sessionEndStatScore', 'homeSoloLabel',
          'categoryTabGenre', 'duelRoundLabel',
        };
        final copied = [
          for (final key in template.keys)
            if (!shared.contains(key) && strings[key] == template[key]) key,
        ];
        expect(copied, isEmpty, reason: 'left in English');
      });
    });
  }
}
