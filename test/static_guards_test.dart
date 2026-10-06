import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static guards for architectural invariants: tests that fail if a
/// forbidden pattern reappears in the source. These catch what behavioural
/// unit tests cannot (a forbidden construction that "works").
void main() {
  late List<File> dartFilesInLib;

  setUp(() {
    dartFilesInLib = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  });

  /// Lines of [file] that are not whole-line comments, with 1-based numbers.
  /// Only whole-line comments are skipped: code is never hidden inside one,
  /// and string literals (e.g. content:// URIs) are left untouched.
  Iterable<(int, String)> codeLines(File file) sync* {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue;
      yield (i + 1, line);
    }
  }

  List<String> findToken(List<File> files, String token) => [
    for (final file in files)
      for (final (lineNo, line) in codeLines(file))
        if (line.contains(token))
          '${file.path}:$lineNo: ${line.trim()}',
  ];

  test('no ConcatenatingAudioSource anywhere in lib/ (invariant 4: '
      'setAudioSources, not the deprecated ConcatenatingAudioSource)', () {
    expect(
      findToken(dartFilesInLib, 'ConcatenatingAudioSource'),
      isEmpty,
      reason: 'invariant 4 broken — ConcatenatingAudioSource reappeared',
    );
  });

  test('no FloatingActionButton anywhere in lib/ (invariant 17: on '
      'Flutter 3.41.7 a scaffold with a FAB suppresses ScaffoldMessenger '
      'snackbars — the A9 skipped-track notice)', () {
    expect(
      findToken(dartFilesInLib, 'FloatingActionButton'),
      isEmpty,
      reason: 'invariant 17 broken — a FloatingActionButton would '
          'suppress snackbars',
    );
  });

  test('no Dart-side parallel queue list in the handler or controller '
      '(invariant 3: the player owns the queue; it was reintroduced once as '
      '_backingQueue)', () {
    final files = [
      File('lib/presentation/services/audio_handler.dart'),
      File('lib/presentation/controllers/playback_controller.dart'),
    ];
    final violations = <String>[];
    for (final file in files) {
      for (final (lineNo, line) in codeLines(file)) {
        // A field declaration: the type starts the declaration (not a
        // parameter, which follows '(', and not a generic argument of
        // another type such as Stream<List<MediaItem>>), on a line that
        // declares/initialises a variable.
        for (final match
            in RegExp(r'List<(MediaItem|SyncedTrack)>').allMatches(line)) {
          final before = match.start > 0 ? line[match.start - 1] : ' ';
          if (before == '<' || before == '(') continue;
          if (line.contains(';') || line.contains('=')) {
            violations.add('${file.path}:$lineNo: ${line.trim()}');
          }
        }
      }
    }
    expect(violations, isEmpty,
        reason:
            'invariant 3 broken — a parallel Dart queue list reappeared:\n'
            '${violations.join('\n')}');
  });

  test('no `--` comment inside a CREATE TABLE string in '
      'database_helper.dart (SQLite stores CREATE TABLE text verbatim in '
      'sqlite_master, comments included — a comment inside the SQL is itself '
      'a fresh-vs-upgraded schema diff; see backlog check C)', () {
    final file = File('lib/data/database/database_helper.dart');
    final source = file.readAsStringSync();
    final violations = <String>[];
    final stringBlocks =
        RegExp("'''(?:[^']|'(?!''))*'''", dotAll: true).allMatches(source);
    for (final block in stringBlocks) {
      final sql = block.group(0)!;
      if (!sql.contains('CREATE TABLE')) continue;
      final offsetInBlock = sql.indexOf('--');
      if (offsetInBlock < 0) continue;
      // Map the hit back to a line number in the file.
      final startLine = source.substring(0, block.start).split('\n').length;
      final lineInBlock = sql.substring(0, offsetInBlock).split('\n').length;
      violations.add(
          '${file.path}:${startLine + lineInBlock - 1} (inside CREATE TABLE string)');
    }
    expect(violations, isEmpty,
        reason:
            'a `--` comment inside a CREATE TABLE string would show up as a '
            'schema diff against the migration path:\n${violations.join('\n')}');
  });
}
