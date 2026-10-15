import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

/// The shared `FlexibleSpaceBar` header for the collection detail screens
/// (playlist / album / artist), keeping one layout owner per visible scroll
/// state.
///
/// `FlexibleSpaceBar` lays out `title` and `background` as **independent
/// layers of one Stack** (Flutter 3.41; see `flexible_space_bar.dart`): the
/// title is anchored to the bar's bottom-left (default padding start 72 /
/// bottom 16 when `centerTitle` is false and a leading widget exists),
/// scaled 1.5 -> 1.0 about that corner as the bar collapses; the background
/// is a parallax layer (up a quarter of the collapse travel) that fades to
/// opacity 0 at full collapse. With `pinned: true` the bar's
/// `toolbarOpacity` is always 1, so the title is fully visible in **every**
/// scroll state, and at full collapse the background is invisible — the
/// title is the collapsed-state owner of the name, and the background's
/// icon/artwork + metadata row is the expanded-state owner.
///
/// The pre-fix layout anchored the row bottom-left too, so both layers
/// claimed the bottom-left region when expanded and the name painted over
/// the icon and the track count (blockers 2026-10-13; the collapsed
/// variant is 2026-10-08). The two placements below keep the layers
/// disjoint in every scroll state:
///
/// * expanded — the row is anchored **top-left**, out of the title's
///   bottom-left zone;
/// * collapsing — the row fades out (ending 8 px before the title sweep
///   would reach it, computed from [FlexibleSpaceBarSettings]), so the
///   sweep never crosses an opaque row;
/// * collapsed — the row is gone (and the background is at opacity 0),
///   leaving the title as the sole visible content.
///
/// The title must keep `maxLines: 1` + ellipsis: a wrapping or unsized
/// title overflows the 56 px collapsed bar (the 2026-10-08 entry's
/// requirement). Guarded by `test/detail_header_geometry_test.dart`.
class CollectionDetailHeader extends StatelessWidget {
  const CollectionDetailHeader({
    super.key,
    required this.name,
    required this.row,
    required this.rowHeight,
  });

  /// The collection name — the FlexibleSpaceBar `title`.
  final String name;

  /// The icon/artwork + metadata row — the expanded-state content. Keep
  /// its internal structure as-is; only this header owns its placement.
  final Widget row;

  /// The height the header pins the row to (icon 64 / avatar 72 / artwork
  /// 120). Without the pin, a row containing an `Expanded` column
  /// stretches to the background's full height and its bottom-aligned
  /// metadata lands in the title zone again; the fade window is also
  /// derived from it, so it must match the row's content.
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    return FlexibleSpaceBar(
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      background: _HeaderRowFade(
        rowHeight: rowHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(height: rowHeight, child: row),
          ),
        ),
      ),
    );
  }
}

/// Fades the expanded-state header row out before the collapsing title
/// sweep reaches it (see [CollectionDetailHeader]).
class _HeaderRowFade extends StatelessWidget {
  const _HeaderRowFade({required this.rowHeight, required this.child});

  final double rowHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FlexibleSpaceBarSettings? settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final double? t = _collapseFraction(settings);
    final double opacity =
        t == null ? 1.0 : _rowOpacity(t, settings!, rowHeight, context);
    return Opacity(opacity: opacity, child: child);
  }

  /// 0 = fully expanded, 1 = fully collapsed. Null when the bar cannot
  /// collapse (or no settings are in scope) — the row then just stays.
  static double? _collapseFraction(FlexibleSpaceBarSettings? settings) {
    if (settings == null) return null;
    final double delta = settings.maxExtent - settings.minExtent;
    if (delta <= 0) return 0.0;
    return clampDouble(
      1.0 - (settings.currentExtent - settings.minExtent) / delta,
      0.0,
      1.0,
    );
  }

  /// The row's opacity at collapse fraction [t].
  ///
  /// The title's painted top and the row's bottom are both **linear** in
  /// [t] (title: `barHeight - 16 - h * (1.5 - 0.5 t)` with [h] the title's
  /// one-line height; row: `24 + rowHeight - delta * t / 4`), so the title
  /// sweep closes the vertical gap at a constant rate. The row therefore
  /// stays opaque until 15% of the collapse before the sweep arrives, then
  /// fades to 0 at the fraction where an 8 px safety margin still remains —
  /// the two layers are disjoint in every scroll state, not just at the
  /// expanded/collapsed extremes the guards measure.
  static double _rowOpacity(
    double t,
    FlexibleSpaceBarSettings settings,
    double rowHeight,
    BuildContext context,
  ) {
    final double delta = settings.maxExtent - settings.minExtent;
    final TextStyle titleStyle = Theme.of(context).textTheme.titleLarge!;
    final double h = (titleStyle.fontSize ?? 22.0) * (titleStyle.height ?? 1.0);
    final double gap0 = 16.0 + delta - 1.5 * h - rowHeight; // gap at t = 0
    final double slope = 0.75 * delta - 0.5 * h; // how fast the gap closes
    if (slope <= 0 || gap0 <= 8.0) {
      // Degenerate: slope <= 0 — the gap never closes (no collision risk);
      // gap0 <= 8 — the row already reaches the title when expanded, so no
      // fade window exists. Either way: fade across the whole collapse.
      return 1.0 - t;
    }
    final double tGone = ((gap0 - 8.0) / slope).clamp(0.05, 0.95);
    final double tStart = (tGone - 0.15).clamp(0.0, tGone);
    if (t <= tStart) return 1.0;
    if (t >= tGone) return 0.0;
    return 1.0 - (t - tStart) / (tGone - tStart);
  }
}
