import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:romsync/src/l10n.dart';
import 'package:romsync_core/romsync_core.dart';

Map<String, Object?> arb(String lang) =>
    jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync()) as Map<String, Object?>;

/// Names of the {placeholders} of an ARB message, plural branches included.
Set<String> placeholders(String text) => {for (final m in RegExp(r'\{(\w+)(?:,|\})').allMatches(text)) m[1]!};

void main() {
  test('every language has the keys and placeholders of French', () {
    final fr = arb('fr');
    final keys = fr.keys.where((k) => !k.startsWith('@')).toSet();
    for (final lang in appLanguages) {
      final other = arb(lang);
      expect(other.keys.where((k) => !k.startsWith('@')).toSet(), keys, reason: lang);
      for (final k in keys) {
        expect(placeholders(other[k]! as String), placeholders(fr[k]! as String), reason: '$lang $k');
        expect((other[k]! as String).trim(), isNotEmpty, reason: '$lang $k');
      }
    }
  });

  test('the system language is followed, English otherwise', () {
    expect(resolveLocale(null, const [Locale('fr', 'CA')]), const Locale('fr'));
    expect(resolveLocale(null, const [Locale('de'), Locale('fr')]), const Locale('fr'));
    expect(resolveLocale(null, const [Locale('de')]), const Locale('en'));
    expect(resolveLocale(null, const []), const Locale('en'));
    expect(resolveLocale('en', const [Locale('fr')]), const Locale('en'));
    expect(resolveLocale('xx', const [Locale('fr')]), const Locale('fr'));
  });

  test('every core message has a sentence in every language', () {
    const args = {
      'count': 2,
      'code': 1,
      'detail': 'd',
      'copy': 'c',
      'gameId': 'IRBF',
      'version': '0.4.0',
      'file': 'f.sav',
      'reason': CoreMessage(Msg.fileChanging),
      'path': '/p',
      'name': 'melonDS',
      'id': 'net.x',
      'folder': '/f',
      'folders': '/a, /b',
      'value': 'v',
      'title': 'Noire',
      'device': 'pc',
      'output': 'o',
    };
    for (final lang in appLanguages) {
      final l = textsFor(Locale(lang));
      for (final code in Msg.values) {
        final text = coreText(l, CoreMessage(code, args));
        expect(text.trim(), isNotEmpty, reason: '$lang ${code.name}');
        expect(text, isNot(contains('{')), reason: '$lang ${code.name}');
      }
    }
    final fr = textsFor(const Locale('fr'));
    expect(
      coreText(fr, CoreMessage(Msg.fileProblem, {'file': 'a.sav', 'reason': const CoreMessage(Msg.fileChanging)})),
      'a.sav : le fichier change pendant la lecture',
    );
    expect(coreText(fr, const CoreMessage(Msg.syncServerTooOld)), contains('antérieure à 0.5.0'));
    expect(
      coreText(textsFor(const Locale('en')), const CoreMessage(Msg.syncOffline, {'count': 1})),
      contains('1 upload waiting'),
    );
  });

  test('sizes and dates follow the language', () {
    final fr = textsFor(const Locale('fr'));
    final en = textsFor(const Locale('en'));
    expect(formatSize(fr, 1536), '1,5 Kio');
    expect(formatSize(en, 1536), '1.5 KiB');
    expect(formatSize(en, 512), '512 B');
    expect(formatSize(fr, 8 << 20), '8 Mio');
    final d = DateTime(2026, 11, 8, 16, 28);
    expect(formatDate(fr, d), '08/11/2026 16:28');
    expect(formatDate(en, d), '2026-11-08 16:28');
  });
}
