import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

/// Vertical gap between the back arrow glyph's bottom and the media's top.
/// The 24 px glyph is centred in the 56 px toolbar zone, so its bottom sits
/// `kToolbarHeight - 16` below the status-inset top; the media's top inset
/// (computed in [CollectionDetailHeader.build]) is that plus this gap, which
/// keeps the media 8 px under the arrow on every device (the status-inset
/// height P varies by device and is read from the MediaQuery).
const double _kMediaArrowGap = 8.0;

/// Start (left) padding for the media.
const double _kMediaStart = 24.0;

/// Trailing padding for the header content.
const double _kMediaEnd = 24.0;

/// The margin between the media's bottom and the bar's bottom when expanded.
/// The call sites size `expandedHeight = kToolbarHeight + mediaSize`, which
/// makes the bar end exactly this margin below the media (top inset 48 +
/// media + this margin = P + 56 + mediaSize); the Play/Shuffle row sits in
/// the next sliver, so the media-to-button gap is this margin + the row's
/// own top padding (8 px) = 16 px. Checked by the assert in
/// [_HeaderFade.build].
const double _kBottomMargin = 8.0;

/// Gap between the media and the name/meta column.
const double _kMediaGap = 16.0;

/// Gap between the name and the meta line.
const double _kNameMetaGap = 4.0;

/// The collapse fraction at which the collapsed-state title starts fading
/// in (fully in by `_kTitleInEnd`). It must stay above the header content's
/// fade-out end on every call site (checked with an assert in
/// [_HeaderFade._headerOpacity]) so the two name renderings never paint at
/// the same time.
const double _kTitleInStart = 0.5;
const double _kTitleInEnd = 0.7;

/// How much of the collapse (as a fraction) the header content's fade
/// starts before it must be gone.
const double _kFadeLead = 0.15;

/// The shared header for the collection detail screens (playlist / album /
/// artist), keeping one layout owner per visible scroll state.
///
/// `FlexibleSpaceBar` lays out `title` and `background` as **independent
/// layers of one Stack** (Flutter 3.41; see `flexible_space_bar.dart`): the
/// title is anchored to the bar's bottom-left (padding start 72 / bottom 16
/// while a leading widget exists), scaled 1.5 -> 1.0 about that corner as
/// the bar collapses; the background is a parallax layer (up a quarter of
/// the collapse travel) that the framework fades to opacity 0 at full
/// collapse. With `pinned: true` the bar's `toolbarOpacity` is always 1.
///
/// The design (2026-10-19, user-specified): when expanded the header reads
/// as one row — the media left-aligned under the back arrow, and to its
/// right the collection **name** above its **meta** line ('N tracks'
/// family) — and that row is the background layer's content. The framework
/// `title` is the same name rendered at the collapsed position (bottom-left,
/// beside the back button) and is the **collapsed-state owner**: it is
/// invisible while expanded and fades in at the end of the collapse, when
/// the background has already gone. Hence:
///
/// * **expanded** — the background owns everything visible (media, name,
///   meta); the framework title is at opacity 0;
/// * **collapsing** — the background fades out (parallax + fade) and the
///   framework title fades in; the header is fully gone exactly when the
///   title starts fading in (fixed hand-off at `_kTitleInStart`), so the
///   two renderings never paint together;
/// * **collapsed** — the background is gone (framework-faded, and its own
///   fade ended), the framework title is fully visible: title + back button
///   only.
///
 /// Compact geometry (2026-10-19): the bar is sized to its content —
 /// `expandedHeight = kToolbarHeight + mediaSize` — so the media's bottom
 /// sits [_kBottomMargin] above the bar's bottom and the Play/Shuffle row
 /// (next sliver) follows 16 px below the media. A taller bar leaves a dead
 /// band between the media and the buttons (the 2026-10-19 defect: 61 px on
 /// the reference Pixel); the assert in [_HeaderFade.build] pins the
 /// `expandedHeight` contract. At an enlarged system text scale the name
 /// keeps the user's scale and the meta (placed in a `Flexible`) yields to
 /// the row's [mediaSize] height cap, so the tight content box never
 /// overflows (at the largest Android scale the meta's box shrinks and its
 /// glyphs may spill a few px into the bottom margin).
 ///
 /// The background also receives the framework's own parallax fade
 /// (`FlexibleSpaceBar` defaults to `CollapseMode.parallax`,
 /// `flexible_space_bar.dart:245-252`): it starts at collapse fraction
 /// `1 - kToolbarHeight / mediaSize` (0.125 / 0.222 / 0.533 for the 64/72/120
 /// call sites), so the *painted* header opacity is that fade times the
 /// [_HeaderFade] window — below 1.0 from early in the collapse on the two
 /// smaller media sizes, and exactly 0 by t = 0.5 either way. The "one
 /// rendering at a time" contract is unaffected: both fades are monotone and
 /// the title starts where the header is exactly 0.
 ///
 /// The fade hand-off is a fixed window, not a derived crossing: in this
 /// compact geometry the collapsed title's sweep band overlaps the expanded
 /// name for the entire range in which the header is visible (t ≤ 0.5) —
 /// they coincide at the hand-off, which is what makes the morph read as the
 /// name settling into the collapsed bar — so the only clean contract is
 /// "one rendering at a time": the header fades out over
 /// `[_kTitleInStart - _kFadeLead, _kTitleInStart]` and the title fades in
 /// over `[_kTitleInStart, _kTitleInEnd]`.
///
/// The expanded name must keep `maxLines: 1` + ellipsis: a wrapping name
/// would break the single-row shape and, in the collapsed bar, the
/// framework's 1-line title overflows the 56 px bar (the 2026-10-08 entry's
/// requirement). Guarded by `test/detail_header_geometry_test.dart`.
///
/// Precondition: call sites use the 56 px default `minExtent`
/// (`kToolbarHeight`), the default `titleLarge` title style, and the
/// framework's default title padding/scale. All current call sites do; with
/// a custom value recompute the insets and fade windows before reusing.
class CollectionDetailHeader extends StatelessWidget {
  const CollectionDetailHeader({
    super.key,
    required this.name,
    required this.media,
    required this.mediaSize,
    this.meta,
  });

  /// The collection name — rendered beside the media when expanded and as
  /// the framework `title` (collapsed position) always.
  final String name;

  /// The media — icon / artwork / avatar, pinned to [mediaSize] square.
  final Widget media;

  /// The media's square side (icon 64 / avatar 72 / artwork 120). The call
  /// site sizes the media widget to this; the pin keeps a media that wants
  /// to stretch (an `Expanded` child, a loose image) from distorting the
  /// row.
  final double mediaSize;

  /// The meta line under the name ('N tracks' family). Styled by the call
  /// site; omitted (null) while the screen is still loading. Placed in a
  /// `Flexible` (see the class doc): at an enlarged system text scale it
  /// yields to the row's [mediaSize] height cap instead of overflowing the
  /// tight content box.
  final Widget? meta;

  @override
  Widget build(BuildContext context) {
    // The background spans the full sliver extent (status inset P plus
    // expandedHeight), so the top inset must be P-aware: it places the
    // media [_kMediaArrowGap] below the back arrow glyph (whose bottom sits
    // `kToolbarHeight - 16` below the inset top) on every device.
    final double topInset =
        MediaQuery.paddingOf(context).top + kToolbarHeight - 16 + _kMediaArrowGap;
    return FlexibleSpaceBar(
      title: _CollapsingTitle(name: name),
      background: _HeaderFade(
        mediaSize: mediaSize,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _kMediaStart,
            topInset,
            _kMediaEnd,
            _kBottomMargin,
          ),
          // Top-pinned: the background arrives with a TIGHT height (the
          // sliver extent minus the padding), which a bare Row would fill —
          // centring the media in the slack and reopening the dead band
          // below it. Align gives the Row loose constraints so it sizes to
          // the media (its tallest child) and stays at the content top.
          child: Align(
            alignment: Alignment.topCenter,
            child: Row(
              children: [
                SizedBox.square(dimension: mediaSize, child: media),
                const SizedBox(width: _kMediaGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        key: const Key('detail-header-expanded-name'),
                        name,
                        style: Theme.of(context).textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (meta != null) ...[
                        const SizedBox(height: _kNameMetaGap),
                        // Flexible: the content box is tight at [mediaSize]
                        // (the _HeaderFade assert), so an unconstrained
                        // name + gap + meta column would RenderFlex-overflow
                        // it at an enlarged system text scale (measured 7 px
                        // on the playlist screen at scale 1.3). The flex cap
                        // makes the meta yield: its box shrinks to the
                        // remaining height and the row stays [mediaSize]
                        // tall. At the default scale the remainder exceeds
                        // the meta's natural height, so this is a no-op.
                        Flexible(child: meta!),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 0 = fully expanded, 1 = fully collapsed. Null when the bar cannot
/// collapse (or no settings are in scope) — callers then keep everything
/// fully visible.
double? _collapseFraction(FlexibleSpaceBarSettings? settings) {
  if (settings == null) return null;
  final double delta = settings.maxExtent - settings.minExtent;
  if (delta <= 0) return null;
  return clampDouble(
    1.0 - (settings.currentExtent - settings.minExtent) / delta,
    0.0,
    1.0,
  );
}

/// The collapsed-state name: the framework `title` slot, hidden while
/// expanded and faded in at the end of the collapse (see
/// [CollectionDetailHeader]). The framework keeps painting it at full
/// `toolbarOpacity` (pinned bar), so the opacity lives here.
class _CollapsingTitle extends StatelessWidget {
  const _CollapsingTitle({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final FlexibleSpaceBarSettings? settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final double? t = _collapseFraction(settings);
    final double opacity =
        t == null ? 1.0 : Interval(_kTitleInStart, _kTitleInEnd).transform(t);
    return Opacity(
      key: const Key('detail-header-collapsed-title'),
      opacity: opacity,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Fades the expanded-state header (media + name + meta) out so it is fully
/// gone exactly when the collapsed-state title starts fading in (see
/// [CollectionDetailHeader]).
class _HeaderFade extends StatelessWidget {
  const _HeaderFade({required this.mediaSize, required this.child});

  final double mediaSize;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FlexibleSpaceBarSettings? settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    if (settings != null) {
      // The compact-geometry contract: the bar must end exactly
      // [_kBottomMargin] below the media, i.e. maxExtent (status inset P
      // plus expandedHeight) = P + kToolbarHeight + mediaSize. A taller
      // bar reopens the dead band between the media and the Play/Shuffle
      // row (the 2026-10-19 defect); a shorter one clips the media.
      final double expectedMaxExtent =
          MediaQuery.paddingOf(context).top + kToolbarHeight + mediaSize;
      assert(
        (settings.maxExtent - expectedMaxExtent).abs() < 1.0,
        'CollectionDetailHeader call site violates the compact-geometry '
        'contract: expandedHeight must be kToolbarHeight + mediaSize '
        '(maxExtent ${settings.maxExtent} != expected $expectedMaxExtent)',
      );
    }
    final double? t = _collapseFraction(settings);
    final double opacity = t == null ? 1.0 : _headerOpacity(t);
    return Opacity(
      key: const Key('detail-header-row-fade'),
      opacity: opacity,
      child: child,
    );
  }

  /// The header's opacity at collapse fraction [t].
  ///
  /// Fixed hand-off at [_kTitleInStart]: the header is fully visible until
  /// `_kTitleInStart - _kFadeLead`, fades linearly to 0 at
  /// [_kTitleInStart], and is gone after. The title fades in over
  /// `[_kTitleInStart, _kTitleInEnd]`, so the two renderings of the name
  /// are never painted together. (In this header's compact geometry the
  /// title's sweep band overlaps the expanded name for the entire range in
  /// which the header is visible (t ≤ 0.5) — they coincide at the hand-off —
  /// so a crossing-derived window would be meaningless; see the
  /// [CollectionDetailHeader] doc.)
  static double _headerOpacity(double t) {
    const double tGone = _kTitleInStart;
    assert(
      _kFadeLead <= tGone && _kTitleInEnd > tGone,
      'CollectionDetailHeader fade windows are broken: the header fade-out '
      'must end exactly when the title fade-in starts',
    );
    final double tStart = (tGone - _kFadeLead).clamp(0.0, tGone);
    if (t <= tStart) return 1.0;
    if (t >= tGone) return 0.0;
    return 1.0 - (t - tStart) / (tGone - tStart);
  }
}
