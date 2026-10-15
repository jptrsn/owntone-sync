// Geometry guards for the three collection detail screen headers
// (playlist / album / artist), per .agent/widget-test-task.md Unit A.
//
// These encode the requirement — spec B3 (.agent/player-ux-spec.md: detail
// header with artwork/title/metadata, collapsing on scroll) plus the two
// blocker entries (.agent/blockers.md 2026-10-13 expanded, 2026-10-08
// collapsed) — NOT current behaviour:
//
//   * expanded: the title does not overlap the icon / AlbumArtTile /
//     CircleAvatar, and does not overlap the meta text ('N tracks' family);
//   * collapsed: the title does not overlap the leading back button, and
//     does not overflow the bar (a maxLines/ellipsis constraint).
//
// This file is EXPECTED TO FAIL on the overlap assertions until Unit B
// fixes the headers. Do not weaken these guards to make them pass
// (constraint 5): a guard that no longer measures overlap is worse than
// none. If an assertion looks wrong, it gets adjudicated, not edited.
//
// Harness notes (full constraints in widget_test_helpers.dart): seeding
// runs in a plain test() (real zone) before the pumps, because FFI SQLite
// I/O never completes under FakeAsync (constraint 1); seeding is
// check-and-insert into the shared FFI DB file (constraint 2); header
// finders are scoped to the FlexibleSpaceBar (constraint 3).
//
// Collapsed phase: with the seeded track counts the lists are shorter than
// the default 800x600 test surface, so the CustomScrollView has no scroll
// extent and cannot be collapsed by dragging. Each test therefore resizes
// the view to 800x170 logical before the collapse phase (the expanded
// header geometry is viewport-independent, so the expanded assertions are
// measured on the same surface the 2026-10-13 probe used). 170 px leaves
// enough scroll extent on every screen for full collapse (the album screen
// is the binding case: ~396 px of content, and full collapse needs 204 px
// of extent), then drags up ~300 px (clamped at the extent) and verifies
// the bar actually collapsed before asserting on it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/presentation/screens/album_detail_screen.dart';
import 'package:owntone_sync/presentation/screens/artist_detail_screen.dart';
import 'package:owntone_sync/presentation/screens/playlist_detail_screen.dart';
import 'package:owntone_sync/presentation/widgets/library_rows.dart';

import 'widget_test_helpers.dart';

/// The header's meta text ('N tracks' family). Scoped to the
/// FlexibleSpaceBar at use sites (constraint 3): the list rows below the
/// header carry their own 'tracks' texts.
final Finder _metaText = find.textContaining('track');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seed: detail screen fixtures (check-and-insert, never delete)', () async {
    await initWidgetTestDb();
    await seedDetailScreens();
  });

  setUp(() {
    mockAppChannels();
  });

  /// Shrinks the viewport so the short seeded lists become scrollable, and
  /// registers the reset for teardown (it runs even when this test is RED).
  void enterCollapsePhase(WidgetTester tester) {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(800, 170);
    tester.view.devicePixelRatio = 1.0;
  }

  /// Drags the screen's CustomScrollView up ~300 px (the task's collapsed
  /// gesture) and lets the scroll settle.
  Future<void> scrollToCollapsed(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The collapsed-state guards: the bar is fully collapsed, the title
  /// clears the leading back button, and the title fits the bar.
  Future<void> assertCollapsed(
    WidgetTester tester,
    String screen,
    String title,
  ) async {
    final bar = globalRect(tester, find.byType(FlexibleSpaceBar));
    // Harness sanity (verification-protocol §4): confirm the measured state
    // is actually the collapsed bar before asserting on it.
    expect(
      bar.height,
      lessThanOrEqualTo(kToolbarHeight + 1),
      reason: '$screen: bar did not fully collapse: $bar',
    );

    final collapsedTitle = headerRect(tester, find.text(title));
    final back = globalRect(tester, find.byIcon(Icons.arrow_back));

    expectNoOverlap(
      '$screen (collapsed) title vs back button',
      collapsedTitle,
      back,
    );
    // The title is constrained by maxLines/ellipsis: a long or wrapping
    // title must not run past the bar's right edge or its bottom edge.
    expect(
      collapsedTitle.right <= bar.right && collapsedTitle.bottom <= bar.bottom,
      isTrue,
      reason: '$screen (collapsed) title overflows the bar: '
          'title=$collapsedTitle bar=$bar',
    );
  }

  group('playlist detail header (expandedHeight 180)', () {
    testWidgets(
      'expanded title clears the icon and track count; '
      'collapsed title clears the back button and fits the bar',
      (tester) async {
        await pumpScreen(
          tester,
          const PlaylistDetailScreen(playlistId: 101, playlistName: 'Brass'),
          ready: find.descendant(
            of: find.byType(FlexibleSpaceBar),
            matching: _metaText,
          ),
        );

        // Expanded — initial load.
        final title = headerRect(tester, find.text('Brass'));
        final icon = headerRect(tester, find.byIcon(Icons.queue_music));
        final meta = headerRect(tester, _metaText);

        expectNoOverlap('playlist (expanded) title vs icon', title, icon);
        expectNoOverlap(
          'playlist (expanded) title vs track count',
          title,
          meta,
        );

        // Collapsed — drag the bar away.
        enterCollapsePhase(tester);
        await tester.pump();
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'playlist', 'Brass');
      },
    );
  });

  group('album detail header (expandedHeight 260)', () {
    testWidgets(
      'expanded title clears the artwork and meta; '
      'collapsed title clears the back button and fits the bar',
      (tester) async {
        await pumpScreen(
          tester,
          const AlbumDetailScreen(
            albumName: 'Album X',
            artistName: 'Artist A',
            albumArtist: 'Artist A',
            year: 1970,
          ),
          ready: find.descendant(
            of: find.byType(FlexibleSpaceBar),
            matching: _metaText,
          ),
        );

        // Expanded — initial load.
        final title = headerRect(tester, find.text('Album X'));
        final art = headerRect(tester, find.byType(AlbumArtTile));
        final meta = headerRect(tester, _metaText);

        expectNoOverlap('album (expanded) title vs artwork', title, art);
        expectNoOverlap('album (expanded) title vs meta', title, meta);

        // Collapsed — drag the bar away.
        enterCollapsePhase(tester);
        await tester.pump();
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'album', 'Album X');
      },
    );
  });

  group('artist detail header (expandedHeight 200)', () {
    testWidgets(
      'expanded title clears the avatar and meta; '
      'collapsed title clears the back button and fits the bar',
      (tester) async {
        await pumpScreen(
          tester,
          const ArtistDetailScreen(artistName: 'Solo Artist'),
          ready: find.descendant(
            of: find.byType(FlexibleSpaceBar),
            matching: _metaText,
          ),
        );

        // Expanded — initial load.
        final title = headerRect(tester, find.text('Solo Artist'));
        final avatar = headerRect(tester, find.byType(CircleAvatar));
        final meta = headerRect(tester, _metaText);

        expectNoOverlap('artist (expanded) title vs avatar', title, avatar);
        expectNoOverlap('artist (expanded) title vs meta', title, meta);

        // Collapsed — drag the bar away.
        enterCollapsePhase(tester);
        await tester.pump();
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'artist', 'Solo Artist');
      },
    );
  });
}
