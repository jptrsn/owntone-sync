// Geometry guards for the three collection detail screen headers
// (playlist / album / artist), per .agent/widget-test-task.md Unit A,
// extended 2026-10-19 for the device-pass finding (the 2026-10-15 top-left
// row anchor painted the icon over the back button and left a dead band
// between row and title; the user then specified the expanded shape: media
// left-aligned under the back arrow, name and meta stacked to its right)
// and again 2026-10-19 for the compact-geometry fix (the 61 px dead band
// between the media and the Play/Shuffle row: the bar is now sized to its
// content, the media bottom sits 8 px above the bar bottom, and the fade
// hand-off to the collapsed title is fixed at t = 0.5).
//
// These encode the requirement — spec B3 (.agent/player-ux-spec.md: detail
// header with artwork/title/metadata, collapsing on scroll) plus the two
// blocker entries (.agent/blockers.md 2026-10-13 expanded, 2026-10-08
// collapsed) and the 2026-10-19 shape — NOT current behaviour:
//
//   * expanded: the media sits 8 px under (not over) the leading back
//     arrow, left-aligned; the name is to the right of the media and above
//     the meta line; the name is one line; the media bottom is 8 px above
//     the bar bottom and the Play button top is 16 px below the media
//     bottom (no dead band);
//   * enlarged text scale: at Android's largest font scale (1.3) the
//     name/meta column yields to the mediaSize row cap (the meta sits in a
//     Flexible — invariant 47, 2026-10-20 review finding) — no flex
//     overflow, the 8/8/16 contract intact;
//   * mid-scroll: early in the collapse the expanded content is still
//     visible and the collapsed-state title is still hidden (no double
//     name); at the t = 0.5 hand-off instant neither rendering is painted;
//     just after it the title owns the name alone;
//   * collapsed: the title is fully visible, does not overlap the leading
//     back button, does not overflow the bar (a maxLines/ellipsis
//     constraint), and the expanded content is fully faded out.
//
// Do not weaken these guards to make them pass (constraint 5): a guard that
// no longer measures the requirement is worse than none. If an assertion
// looks wrong, it gets adjudicated, not edited.
//
// Harness notes (full constraints in widget_test_helpers.dart): seeding
// runs in a plain test() (real zone) before the pumps, because FFI SQLite
// I/O never completes under FakeAsync (constraint 1); seeding is
// check-and-insert into the shared FFI DB file (constraint 2); header
// finders are scoped to the FlexibleSpaceBar (constraint 3).
//
// The expanded name (background layer) and the collapsed title (framework
// title slot) are two renderings of the same string, so finders address
// them by key (declared in collection_detail_header.dart), never by text.
//
// Collapsed phase: with the seeded track counts the lists are shorter than
// the default 800x600 test surface, so the CustomScrollView has no scroll
// extent and cannot be collapsed by dragging. Each test therefore resizes
// the view to 800x170 logical before the collapse phase (the expanded
// header geometry is viewport-independent, so the expanded assertions are
// measured on the same surface the 2026-10-13 probe used). 170 px leaves
// enough scroll extent on every screen for full collapse (the album screen
// is the binding case), then drags up ~300 px (clamped at the extent) and
// verifies the bar actually collapsed before asserting on it.

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

/// The expanded-state name (background layer), addressed by the key
/// declared in collection_detail_header.dart.
final Finder _expandedName =
    find.byKey(const Key('detail-header-expanded-name'));

/// The collapsed-state title (framework title slot), addressed by the key
/// declared in collection_detail_header.dart.
final Finder _collapsedTitleText = find.descendant(
  of: find.byKey(const Key('detail-header-collapsed-title')),
  matching: find.byType(Text),
);

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

  /// The opacity of the expanded content's fade (key declared in
  /// collection_detail_header.dart).
  double rowFadeOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.byKey(const Key('detail-header-row-fade')))
      .opacity;

  /// The opacity of the collapsed-state title's fade.
  double titleOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find.byKey(const Key('detail-header-collapsed-title')))
      .opacity;

  /// Drags the screen's CustomScrollView up ~300 px (the task's collapsed
  /// gesture) and lets the scroll settle.
  Future<void> scrollToCollapsed(WidgetTester tester) async {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Jumps the screen's CustomScrollView to an exact [offset] (collapse
  /// fraction t = offset / delta, delta = expandedHeight - kToolbarHeight)
  /// and returns the bar rect. A gesture drag cannot be used here: small
  /// offsets are below the vertical drag touch slop, so the scroll would
  /// never start.
  Future<Rect> scrollToOffset(WidgetTester tester, double offset) async {
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(offset);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return globalRect(tester, find.byType(FlexibleSpaceBar));
  }

  /// The expanded-state guards (user-specified 2026-10-19 shape): the media
  /// is 8 px under the back arrow, left-aligned; the name is to the right
  /// of the media and above the meta; the name is one line; the media
  /// bottom is 8 px above the bar bottom and the Play button follows 16 px
  /// below the media (the compact-geometry contract, no dead band).
  void assertExpanded(
    WidgetTester tester,
    String screen,
    Finder media,
  ) {
    final name = globalRect(tester, _expandedName);
    final m = globalRect(tester, media);
    final meta = headerRect(tester, _metaText);
    final back = globalRect(tester, find.byIcon(Icons.arrow_back));

    // The media sits exactly 8 px under the back arrow glyph, not over it
    // (2026-10-19: the top-left anchor painted the icon over the arrow by
    // ~28 x 28 px). The inset is P-independent by construction (top inset
    // P + kToolbarHeight - 16 + 8 vs the glyph bottom P + 40), so the
    // contract is exactly 8; the 1 px epsilon covers physical-pixel
    // quantization. A looser band would admit fresh dead space between the
    // arrow and the media (2026-10-20 review finding).
    expect(
      m.top,
      moreOrLessEquals(back.bottom + 8.0, epsilon: 1.0),
      reason: '$screen (expanded) media not 8 px under the back arrow: '
          'media=$m back=$back',
    );
    // Left-aligned: the media starts near the screen's left edge, not
    // indented to the title's 72 px start.
    expect(
      m.left,
      lessThan(48),
      reason: '$screen (expanded) media not left-aligned: media=$m',
    );
    // The name is to the right of the media.
    expect(
      name.left >= m.right + 8,
      isTrue,
      reason: '$screen (expanded) name not to the right of the media: '
          'name=$name media=$m',
    );
    // ...and above the meta line.
    expect(
      name.bottom <= meta.top,
      isTrue,
      reason: '$screen (expanded) name not above the meta: name=$name '
          'meta=$meta',
    );
    // One line: M3 titleLarge is 22 x 1.27 = 28 px tall (invariant 47);
    // allow metric slack, but not a second line.
    expect(
      name.height,
      lessThanOrEqualTo(34),
      reason: '$screen (expanded) name is not one line: name=$name',
    );
    // Compact geometry (2026-10-19): the bar ends 8 px below the media —
    // the fade box (key declared in collection_detail_header.dart) spans
    // the whole background, so its bottom is the bar's bottom.
    final barBottom =
        globalRect(tester, find.byKey(const Key('detail-header-row-fade')))
            .bottom;
    expect(
      barBottom - m.bottom,
      moreOrLessEquals(8.0, epsilon: 1.0),
      reason: '$screen (expanded) bar bottom not 8 px below the media '
          '(dead band or clip): media=$m barBottom=$barBottom',
    );
    // ...and the Play button (next sliver, 8 px top padding) follows 16 px
    // below the media bottom — the user's 2026-10-19 "no dead band between
    // header and buttons" requirement.
    final play = globalRect(tester, find.widgetWithText(FilledButton, 'Play'));
    expect(
      play.top > m.bottom,
      isTrue,
      reason: '$screen (expanded) Play button above the media bottom: '
          'play=$play media=$m',
    );
    expect(
      play.top - m.bottom,
      moreOrLessEquals(16.0, epsilon: 1.0),
      reason: '$screen (expanded) dead band between media and Play button: '
          'media=$m play=$play',
    );
  }

  /// The mid-scroll guards ([delta] = expandedHeight - kToolbarHeight):
  /// early in the collapse the expanded content is still fully visible and
  /// the collapsed title is still hidden; at the t = 0.5 hand-off instant
  /// neither rendering is painted (the fixed hand-off contract: the header
  /// fades out over [0.35, 0.5], the title fades in over [0.5, 0.7]); just
  /// after it the title owns the name alone. No scroll state paints the
  /// name twice.
  Future<void> assertMidScroll(
    WidgetTester tester,
    String screen,
    double delta,
  ) async {
    // Early mid (t ≈ 0.12-0.23, below the _HeaderFade window's start at
    // 0.35). The framework's own parallax fade (invariant 47) is already
    // dimming the painted background on the smaller media sizes — this
    // assertion reads the keyed _HeaderFade opacity, not the painted
    // product.
    final bar = await scrollToOffset(tester, 15.0);
    // Harness sanity (verification-protocol §4): confirm the measured state
    // is actually a partially collapsed bar before asserting on it.
    expect(
      bar.height > kToolbarHeight + 1,
      isTrue,
      reason: '$screen (mid): bar fully collapsed already: $bar',
    );
    expect(
      rowFadeOpacity(tester),
      greaterThanOrEqualTo(0.99),
      reason: '$screen (mid) expanded content already faded: '
          'opacity=${rowFadeOpacity(tester)}',
    );
    expect(
      titleOpacity(tester),
      lessThanOrEqualTo(0.05),
      reason: '$screen (mid) collapsed title already visible: '
          'opacity=${titleOpacity(tester)}',
    );
    final name = globalRect(tester, _expandedName);
    final meta = headerRect(tester, _metaText);
    expectNoOverlap('$screen (mid-scroll) name vs meta', name, meta);

    // The hand-off instant (t = 0.5): the header is exactly gone and the
    // title has exactly started — one instant with neither painting, so
    // the name is never visible twice (and never invisible for a stretch).
    await scrollToOffset(tester, 0.5 * delta);
    expect(
      rowFadeOpacity(tester),
      lessThan(0.01),
      reason: '$screen (hand-off) expanded content still visible: '
          'opacity=${rowFadeOpacity(tester)}',
    );
    expect(
      titleOpacity(tester),
      lessThan(0.01),
      reason: '$screen (hand-off) collapsed title already visible: '
          'opacity=${titleOpacity(tester)}',
    );

    // Just past the hand-off (t = 0.6): the title owns the name alone
    // (Interval(0.5, 0.7) -> 0.5).
    await scrollToOffset(tester, 0.6 * delta);
    expect(
      rowFadeOpacity(tester),
      lessThan(0.001),
      reason: '$screen (post-hand-off) expanded content still visible: '
          'opacity=${rowFadeOpacity(tester)}',
    );
    expect(
      titleOpacity(tester),
      greaterThan(0.4),
      reason: '$screen (post-hand-off) collapsed title not fading in: '
          'opacity=${titleOpacity(tester)}',
    );
  }

  /// The collapsed-state guards: the bar is fully collapsed, the title is
  /// fully visible, clears the leading back button, and fits the bar, and
  /// the expanded content is fully faded out.
  Future<void> assertCollapsed(WidgetTester tester, String screen) async {
    final bar = globalRect(tester, find.byType(FlexibleSpaceBar));
    // Harness sanity (verification-protocol §4): confirm the measured state
    // is actually the collapsed bar before asserting on it.
    expect(
      bar.height,
      lessThanOrEqualTo(kToolbarHeight + 1),
      reason: '$screen: bar did not fully collapse: $bar',
    );

    final collapsedTitle = globalRect(tester, _collapsedTitleText);
    final back = globalRect(tester, find.byIcon(Icons.arrow_back));

    // The collapsed-state title must actually be the visible name now.
    expect(
      titleOpacity(tester),
      greaterThanOrEqualTo(0.99),
      reason: '$screen (collapsed) title not fully visible: '
          'opacity=${titleOpacity(tester)}',
    );
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
    // The expanded content (media + name + meta) is gone, leaving title +
    // back button as the bar's sole content (invariant 47).
    expect(
      rowFadeOpacity(tester),
      lessThan(0.001),
      reason: '$screen (collapsed) expanded content still visible: '
          'opacity=${rowFadeOpacity(tester)}',
    );
  }

  group('playlist detail header (expandedHeight 120)', () {
    testWidgets(
      'expanded media 8px under back arrow, name right of media above '
      'meta, media bottom 8px above bar bottom, Play 16px below media; '
      'mid-scroll: content visible then t=0.5 hand-off then title alone; '
      'collapsed title visible, clears back button, fits bar; content '
      'faded out',
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
        assertExpanded(tester, 'playlist', find.byIcon(Icons.queue_music));

        // Mid-scroll — partial collapse (delta = 120 - kToolbarHeight).
        enterCollapsePhase(tester);
        await tester.pump();
        await assertMidScroll(tester, 'playlist', 120 - kToolbarHeight);

        // Collapsed — drag the bar away.
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'playlist');
      },
    );
  });

  group('album detail header (expandedHeight 176)', () {
    testWidgets(
      'expanded media 8px under back arrow, name right of media above '
      'meta, media bottom 8px above bar bottom, Play 16px below media; '
      'mid-scroll: content visible then t=0.5 hand-off then title alone; '
      'collapsed title visible, clears back button, fits bar; content '
      'faded out',
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
        assertExpanded(tester, 'album', find.byType(AlbumArtTile));

        // Mid-scroll — partial collapse (delta = 176 - kToolbarHeight).
        enterCollapsePhase(tester);
        await tester.pump();
        await assertMidScroll(tester, 'album', 176 - kToolbarHeight);

        // Collapsed — drag the bar away.
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'album');
      },
    );
  });

  group('artist detail header (expandedHeight 128)', () {
    testWidgets(
      'expanded media 8px under back arrow, name right of media above '
      'meta, media bottom 8px above bar bottom, Play 16px below media; '
      'mid-scroll: content visible then t=0.5 hand-off then title alone; '
      'collapsed title visible, clears back button, fits bar; content '
      'faded out',
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
        assertExpanded(tester, 'artist', find.byType(CircleAvatar));

        // Mid-scroll — partial collapse (delta = 128 - kToolbarHeight).
        enterCollapsePhase(tester);
        await tester.pump();
        await assertMidScroll(tester, 'artist', 128 - kToolbarHeight);

        // Collapsed — drag the bar away.
        await scrollToCollapsed(tester);
        await assertCollapsed(tester, 'artist');
      },
    );
  });

  group('playlist detail header (enlarged text scale)', () {
    testWidgets(
      'at the largest Android font scale (1.3) the meta yields to the '
      'row height cap: no flex overflow, the 8/8/16 contract holds, '
      'the scale is applied (invariant 47)',
      (tester) async {
        // The test binding is per-test, so the value cannot leak into other
        // tests; cleared after the pump for hygiene.
        tester.view.platformDispatcher.textScaleFactorTestValue = 1.3;
        await pumpScreen(
          tester,
          const PlaylistDetailScreen(playlistId: 101, playlistName: 'Brass'),
          ready: find.descendant(
            of: find.byType(FlexibleSpaceBar),
            matching: _metaText,
          ),
        );
        tester.view.platformDispatcher.clearTextScaleFactorTestValue();

        // If the meta's Flexible cap were absent, the pump above would have
        // thrown "A RenderFlex overflowed" on the tight 64 px content box
        // (the 2026-10-20 review probe measured 7 px at this scale) —
        // reaching this point is the primary guard.
        final m = globalRect(tester, find.byIcon(Icons.queue_music));
        final name = globalRect(tester, _expandedName);
        final meta = headerRect(tester, _metaText);
        final barBottom =
            globalRect(tester, find.byKey(const Key('detail-header-row-fade')))
                .bottom;
        final play =
            globalRect(tester, find.widgetWithText(FilledButton, 'Play'));

        // Harness sanity (§4): the scale is actually applied — the
        // one-line name is 22 x 1.27 x 1.3 ≈ 36 px, not the default 28;
        // a wrapped second line (~72 px) fails the same band.
        expect(
          name.height,
          moreOrLessEquals(28 * 1.3, epsilon: 2.5),
          reason: 'text scale not applied or name wrapped: name=$name',
        );
        expectNoOverlap('playlist (scale 1.3) name vs meta', name, meta);
        // The tight content box stayed 64 px tall: the bar still ends 8 px
        // below the media...
        expect(
          barBottom - m.bottom,
          moreOrLessEquals(8.0, epsilon: 1.0),
          reason: 'scale broke the compact-geometry contract: media=$m '
              'barBottom=$barBottom',
        );
        // ...the meta's box yields into the cap (it does not grow the row
        // past the media)...
        expect(
          meta.bottom,
          lessThanOrEqualTo(m.bottom + 1.0),
          reason: 'meta box grew the row past the media: meta=$meta '
              'media=$m',
        );
        // ...and the Play row still follows 16 px below the media.
        expect(
          play.top - m.bottom,
          moreOrLessEquals(16.0, epsilon: 1.0),
          reason: 'scale broke the media-to-Play gap: media=$m play=$play',
        );
      },
    );
  });
}
