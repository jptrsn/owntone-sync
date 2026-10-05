import 'package:flutter/material.dart';

import 'mini_player.dart';

/// Composes [body] with the docked [MiniPlayer].
///
/// The body and the mini player are siblings in a Column: the body is
/// genuinely shrunk to the space above the mini player, so the last row of
/// any list stays reachable. [MiniPlayer] occupies zero height when no track
/// is loaded, in which case the body uses the full height.
///
/// The mini player must never be a Positioned overlay or a
/// Scaffold.bottomSheet: both float over the body without insetting it
/// (bottomSheet is not one of the slots that shrink the body), and the last
/// list row ends up covered.
class PlayerScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;

  const PlayerScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      drawer: drawer,
      body: Column(
        children: [
          Expanded(child: body),
          const SafeArea(top: false, child: MiniPlayer()),
        ],
      ),
    );
  }
}
