import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';

import 'db_lifecycle_helpers.dart';

/// Every lifecycle here runs in its own isolate (`Isolate.run`) because
/// `DatabaseHelper` caches its `Database` in a static that `close()` never
/// clears, and `flutter test` runs files in parallel — one file, one shared
/// DB file, sequential lifecycles is the only safe shape.

/// Rethrows as a plain [Exception]: sqflite exceptions carry the live
/// FfiDatabase in their `details`, which cannot cross the Isolate.run
/// boundary, and would otherwise mask the real failure.
Future<Map<String, Object?>> runLifecycle(
  Future<Map<String, Object?>> Function() lifecycle,
) async {
  try {
    return await lifecycle();
  } catch (e) {
    throw Exception('database lifecycle failed: $e');
  }
}

void main() {
  group('check C: fresh v8 vs v3->v8 migrated (backlog: unverified DDL fix)',
      () {
    late Map<String, Object?> freshSchema;
    late Map<String, Object?> migratedSchema;
    late Map<String, Object?> migratedRows;

    setUpAll(() async {
      // The two lifecycles that must never diverge again: a fresh install
      // runs _createDB, every v0.1.8 user ran _onUpgrade(3, 8). A divergence
      // between the two paths is the bug class that silently broke
      // sync_history on fresh installs (invariant 8, RESOLVED Phase 7) —
      // this test is the standing regression check for it.
      freshSchema = await Isolate.run(() => runLifecycle(freshV8Lifecycle));
      final migrated =
          await Isolate.run(() => runLifecycle(seededV3ToV8Lifecycle));
      migratedSchema = migrated['schema']! as Map<String, Object?>;
      migratedRows = migrated['rows']! as Map<String, Object?>;
    });

    test(
        'migrated v8 schema is identical to fresh v8: every table, index, '
        'column name, type, default and order', () {
      final diffs = schemaDiffs(freshSchema, migratedSchema);
      expect(
        diffs,
        isEmpty,
        reason: 'fresh-vs-upgraded schema diverges:\n${diffs.join('\n')}',
      );
    });

    test('fresh v8 has the sync_history event columns the v0.1.8 installs '
        'lacked (the original defect class)', () {
      final columns = (freshSchema['tables']! as Map)['sync_history']!
          as Map<String, Object?>;
      final names = (columns['columns']! as List)
          .map((c) => (c as Map)['name'])
          .toList();
      expect(names, containsAll(['plays_synced', 'skips_synced']));
    });

    test('data preservation: rows written at v3 survive the full v3->v8 '
        'chain intact', () {
      final expected = expectedPreservedRows();
      final failures = <String>[];
      for (final entry in expected.entries) {
        final table = entry.key;
        final want = (entry.value as List).cast<Map<String, Object?>>();
        final got = (migratedRows[table]! as List).cast<Map<String, Object?>>();
        if (got.length != want.length) {
          failures.add('$table: ${got.length} rows after migration, '
              'wrote ${want.length} at v3');
          continue;
        }
        for (var i = 0; i < want.length; i++) {
          if (!deepEquals(got[i], want[i])) {
            failures.add('$table row $i: migrated=${got[i]} expected=${want[i]}');
          }
        }
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });
  });

  test('v5 purge: non-/tree/ content_uri values are blanked, tree-scoped '
      'ones survive (invariant 6, related safeguards)', () async {
    final result = await Isolate.run(() => runLifecycle(v5PurgeLifecycle));
    expect(result['user_version'], 8);
    // id 1 bare document URI -> purged to ''; id 2 tree URI -> untouched;
    // id 3 NULL -> NULL; id 4 '' -> ''.
    expect(result['uris'], [
      '',
      'content://com.android.externalstorage.documents/tree/primary%3AMusic'
      '/document/primary%3AMusic%2Fb.mp3',
      null,
      '',
    ]);
  });

  test('v6: adds plays_synced/skips_synced when absent, deletes orphaned '
      'sync_history_playlists rows, creates playback_state (invariant 8)',
      () async {
    final result = await Isolate.run(() => runLifecycle(v6Lifecycle));
    expect(result['user_version'], 8);
    final columns = result['history_columns']! as List;
    expect(columns, containsAll(['plays_synced', 'skips_synced']));
    expect(columns.where((c) => c == 'plays_synced').length, 1);
    expect(columns.where((c) => c == 'skips_synced').length, 1);
    final children = (result['children']! as List)
        .map((r) => (r as Map)['playlist_name'])
        .toList();
    expect(children, ['Kept']);
    expect(result['tables']! as List, contains('playback_state'));
  });

  test('v7: adds the rating column and the pending_track_edits table '
      '(invariant 30: the edit row is the retry record)', () async {
    final result = await Isolate.run(() => runLifecycle(v7Lifecycle));
    final rating = result['rating']! as Map;
    expect(rating['name'], 'rating');
    expect(rating['type'], 'INTEGER');
    expect(rating['notnull'], 1);
    expect(rating['dflt_value'], '0');
    expect(result['tables']! as List, contains('pending_track_edits'));
    expect(result['pending_track_edits_columns']! as List, [
      'track_id',
      'field',
      'new_value',
      'base_value',
      'updated_at',
    ]);
    // Pre-existing rows take the column default.
    expect(result['seeded_track_rating'], 0);
  });

  test('v8: adds artwork_source, the negative cache column '
      '(invariant 35)', () async {
    final result = await Isolate.run(() => runLifecycle(v8Lifecycle));
    final artwork = result['artwork_source']! as Map;
    expect(artwork['name'], 'artwork_source');
    expect(artwork['type'], 'TEXT');
    expect(artwork['notnull'], 0);
    expect(artwork['dflt_value'], isNull);
  });

  test('v6 guard: a DB whose sync_history already has the event columns '
      'must not fail or double-add (invariant 8)', () async {
    final result = await Isolate.run(() => runLifecycle(v6IdempotentLifecycle));
    expect(result['user_version'], 8);
    final columns = result['columns']! as List;
    expect(columns.where((c) => c == 'plays_synced').length, 1);
    expect(columns.where((c) => c == 'skips_synced').length, 1);
  });

  test('v8 guard: a DB whose synced_tracks already has artwork_source must '
      'not fail or double-add (invariant 35; the Kotlin worker relies on '
      'the same presence guard)', () async {
    final result = await Isolate.run(() => runLifecycle(v8IdempotentLifecycle));
    expect(result['user_version'], 8);
    expect(result['artwork_source_column_count'], 1);
  });

  group('harness self-check (protocol §4: the comparator must see diffs)',
      () {
    Map<String, Object?> sampleSnapshot() => {
      'user_version': 8,
      'tables': {
        't': {
          'columns': [
            {'name': 'a', 'type': 'TEXT', 'notnull': 0, 'dflt_value': null, 'pk': 0},
            {'name': 'b', 'type': 'INTEGER', 'notnull': 1, 'dflt_value': '0', 'pk': 1},
          ],
          'indexes': {
            'idx': {'unique': 0, 'origin': 'c', 'columns': ['a']},
          },
          'foreign_keys': [
            {'ref': 'u', 'from': 'b', 'to': 'id', 'on_update': 'NO ACTION', 'on_delete': 'NO ACTION', 'match': 'NONE'},
          ],
        },
      },
    };

    test('identical snapshots produce no diffs', () {
      expect(schemaDiffs(sampleSnapshot(), sampleSnapshot()), isEmpty);
    });

    test('an injected column default change is detected', () {
      final a = sampleSnapshot();
      final b = sampleSnapshot();
      final bCol = (b['tables']! as Map)['t']! as Map;
      (bCol['columns']! as List)[0]['dflt_value'] = '';
      expect(schemaDiffs(a, b), isNotEmpty);
    });

    test('an injected column reorder is detected', () {
      final a = sampleSnapshot();
      final b = sampleSnapshot();
      final bCols = (b['tables']! as Map)['t']! as Map;
      final original = List<Object?>.of(bCols['columns']! as List);
      bCols['columns'] = [original[1], original[0]];
      expect(schemaDiffs(a, b), isNotEmpty);
    });

    test('a dropped index is detected', () {
      final a = sampleSnapshot();
      final b = sampleSnapshot();
      final bTable = (b['tables']! as Map)['t']! as Map;
      (bTable['indexes']! as Map).remove('idx');
      expect(schemaDiffs(a, b), isNotEmpty);
    });
  });
}
