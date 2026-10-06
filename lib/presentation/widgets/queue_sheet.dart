import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../services/queue_indices.dart';

/// Presents the queue sheet as a modal bottom sheet above Now Playing.
///
/// The list is the queue stream, which carries PLAY order (base order with
/// shuffleIndices applied), so rows are play positions. The two
/// play-order <-> base translations (see the index-space invariant):
/// - highlight row: play position of the current base index
/// - jump from row i: base index `shuffleIndices[i]` when shuffle is on
void showQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const QueueSheet(),
  );
}

class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key});

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  final ScrollController _scrollController = ScrollController();

  /// Probe attached to row 0 (always built at initial offset) to measure the
  /// real row height — rows are layout-dependent, so no fixed offset is used.
  final GlobalKey _rowHeightProbeKey = GlobalKey();
  bool _autoScrollScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoScroll(int? row) {
    if (_autoScrollScheduled || row == null || row == 0) return;
    _autoScrollScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final probe = _rowHeightProbeKey.currentContext?.findRenderObject();
      final rowHeight = probe is RenderBox ? probe.size.height : 88.0;
      final maxExtent = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(
        (row * rowHeight).clamp(0.0, maxExtent).toDouble(),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _jump(int row, List<int> shuffleIndices, bool shuffleOn) {
    final base = queueBaseIndexForRow(row, shuffleIndices, shuffleOn);
    context.read<PlaybackController>().jumpTo(base);
  }

  void _remove(MediaItem item) {
    context.read<PlaybackController>().removeFromQueue(item);
  }

  void _clearQueue(PlaybackController controller) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear queue?'),
        content: const Text('This stops playback and removes all queued tracks.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await controller.clearQueue();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final colorScheme = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Queue',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'Clear queue',
                  icon: const Icon(Icons.clear_all, size: 24),
                  onPressed: () => _clearQueue(controller),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<MediaItem>>(
              stream: controller.queue,
              builder: (context, queueSnapshot) {
                final items = queueSnapshot.data ?? const <MediaItem>[];
                return StreamBuilder<PlaybackState>(
                  stream: controller.playbackState,
                  builder: (context, stateSnapshot) {
                    final state = stateSnapshot.data;
                    final shuffleOn =
                        state?.shuffleMode == AudioServiceShuffleMode.all;
                    final baseIndex = state?.queueIndex;
                    return StreamBuilder<List<int>>(
                      stream: controller.shuffleIndices,
                      builder: (context, shuffleSnapshot) {
                        final shuffleIndices = shuffleSnapshot.data ??
                            const <int>[];
                        final currentRow = queueCurrentRow(
                          shuffleIndices,
                          baseIndex,
                          shuffleOn,
                        );
                        _scheduleAutoScroll(currentRow);

                        final seen = <String, int>{};
                        final keys = <Object>[
                          for (final item in items)
                            ValueKey(
                              'queue-${item.id}:${seen.update(item.id, (v) => v + 1, ifAbsent: () => 1)}',
                            ),
                        ];

                        if (items.isEmpty) {
                          return const Center(child: Text('Queue is empty'));
                        }

                        return ReorderableListView(
                          scrollController: _scrollController,
                          buildDefaultDragHandles: true,
                          onReorder: (from, to) {
                            controller.moveQueueItem(from, to);
                          },
                          children: [
                            for (var i = 0; i < items.length; i++)
                              Dismissible(
                                key: ValueKey(
                                  'queue-dismiss-${keys[i]}',
                                ),
                                direction: DismissDirection.endToStart,
                                background: Container(
                                  color: colorScheme.error,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Icon(
                                    Icons.delete,
                                    color: colorScheme.onError,
                                  ),
                                ),
                                onDismissed: (_) => _remove(items[i]),
                                child: KeyedSubtree(
                                  key: i == 0 ? _rowHeightProbeKey : null,
                                  child: Material(
                                    color: i == currentRow
                                        ? colorScheme.primary.withValues(
                                            alpha: 0.12,
                                          )
                                        : Colors.transparent,
                                    child: ListTile(
                                      onTap: () => _jump(
                                        i,
                                        shuffleIndices,
                                        shuffleOn,
                                      ),
                                      title: Text(
                                      items[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: i == currentRow
                                          ? TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.primary,
                                            )
                                          : null,
                                    ),
                                    subtitle: Text(
                                      items[i].artist ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      tooltip: 'More',
                                      onSelected: (value) async {
                                        switch (value) {
                                          case 'remove':
                                            _remove(items[i]);
                                          case 'top':
                                            controller.moveQueueItem(i, 0);
                                           case 'bottom':
                                             controller.moveQueueItem(
                                               i,
                                               items.length - 1,
                                             );
                                         }
                                       },
                                      itemBuilder: (_) => [
                                        const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remove'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'top',
                                          child: Text('Move to top'),
                                        ),
                                         const PopupMenuItem(
                                           value: 'bottom',
                                           child: Text('Move to bottom'),
                                         ),
                                        ],
                                     ),
                                   ),
                                 ),
                               ),
                             ),
                           ],
                         );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
