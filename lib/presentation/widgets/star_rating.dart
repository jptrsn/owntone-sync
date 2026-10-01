import 'package:flutter/material.dart';

/// The number of half-stars (0-10) that [rating] (0-100) renders as.
///
/// Display rule: round to the nearest half-star, ties round up — in half-star
/// units, `round(rating / 10)`. So 55 renders as 6 half-stars (3 stars), 62 as
/// 6, 50 as 5 (2.5 stars). Server ratings that do not sit on a half-star
/// boundary (the server accepts any 0-100 integer) render at their nearest
/// half-star; editing such a track snaps it to a multiple of 10.
int ratingToHalfStars(int rating) => (rating.clamp(0, 100) / 10).round();

IconData _starIconData(int index, int halfStars) {
  if (halfStars >= (index + 1) * 2) return Icons.star;
  if (halfStars == index * 2 + 1) return Icons.star_half;
  return Icons.star_border;
}

Widget _starIcon(int index, int halfStars, {required double size, required Color lit}) {
  final isLit = halfStars > index * 2;
  return Icon(
    _starIconData(index, halfStars),
    size: size,
    color: isLit ? lit : Colors.grey[400],
  );
}

/// Compact read-only star rendering for track rows.
class StarRatingDisplay extends StatelessWidget {
  final int rating;
  final double size;
  final Color? color;

  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.size = 14,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final halfStars = ratingToHalfStars(rating);
    final lit = color ?? Colors.amber;
    return Semantics(
      label: 'Rated ${(halfStars / 2).toStringAsFixed(1)} of 5',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 5; i++)
            _starIcon(i, halfStars, size: size, lit: lit),
        ],
      ),
    );
  }
}

/// Interactive five-star control with half-star precision.
///
/// The gesture is press-and-drag and RELATIVE to the grab: the rating at the
/// moment of the press is the baseline, and horizontal movement adjusts it.
/// A full screen-width sweep spans 0-5 stars (one half-star is 10% of the
/// screen width). Vertical movement is ignored, so the finger can drift clear
/// of the stars without losing the gesture. The value commits on release.
class RatingControl extends StatefulWidget {
  /// The rating (0-100) to display and use as the grab baseline.
  final int rating;

  /// Called on every release with the settled value, including an unchanged
  /// one — callers no-op a value equal to the current rating.
  final ValueChanged<int> onCommit;

  /// Called the moment a drag begins, before any movement.
  final VoidCallback? onDragStart;

  /// Called when the control is tapped without dragging.
  final VoidCallback? onTap;

  final double size;

  const RatingControl({
    super.key,
    required this.rating,
    required this.onCommit,
    this.onDragStart,
    this.onTap,
    this.size = 28,
  });

  @override
  State<RatingControl> createState() => _RatingControlState();
}

class _RatingControlState extends State<RatingControl> {
  int _display = 0;
  int _base = 0;
  double _startX = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _display = widget.rating;
    _base = widget.rating;
  }

  @override
  void didUpdateWidget(RatingControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rating != widget.rating && !_dragging) {
      _display = widget.rating;
      _base = widget.rating;
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
    _base = _display;
    _startX = details.globalPosition.dx;
    widget.onDragStart?.call();
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    final width = MediaQuery.sizeOf(context).width;
    if (width <= 0) return;
    final delta = (details.globalPosition.dx - _startX) / width * 100.0;
    final snapped = (((_base + delta) / 10).round()).clamp(0, 10) * 10;
    if (snapped != _display) setState(() => _display = snapped);
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    widget.onCommit(_display);
  }

  @override
  Widget build(BuildContext context) {
    final halfStars = ratingToHalfStars(_display);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 5; i++)
              _starIcon(i, halfStars, size: widget.size, lit: Colors.amber),
          ],
        ),
      ),
    );
  }
}
