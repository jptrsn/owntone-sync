import 'package:flutter/material.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/models/sync_history.dart';
import '../widgets/player_scaffold.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();
  List<SyncHistoryRecord> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final history = await _dbRepo.getSyncHistory();
    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return 'N/A';
    final duration = Duration(milliseconds: durationMs);
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes % 60}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'partial':
        return Colors.amber;
      case 'cancelled':
        return Colors.orange;
      case 'skipped':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'success':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'partial':
        return Icons.sync_problem;
      case 'cancelled':
        return Icons.cancel;
      case 'skipped':
        return Icons.skip_next;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    // PlayerScaffold: the mini player survives navigating here (Phase U2
    // build item 1); zero-height at idle.
    return PlayerScaffold(
      appBar: AppBar(
        title: const Text('Sync History'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadHistory,
              child: ListView.builder(
                itemCount: _history.length,
                itemBuilder: (context, index) {
                  final record = _history[index];
                  return _buildHistoryItem(record);
                },
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No Sync History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Sync history will appear here',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(SyncHistoryRecord record) {
    final statusColor = _getStatusColor(record.status);
    final statusIcon = _getStatusIcon(record.status);
    final plays = record.playsSynced ?? 0;
    final skips = record.skipsSynced ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Row(
          children: [
            Expanded(
              child: Text(
                record.status == 'success'
                    ? 'Sync Completed'
                    : record.status == 'failed'
                    ? 'Sync Failed'
                    : record.status == 'cancelled'
                    ? 'Sync Cancelled'
                    : record.status == 'partial'
                    ? 'Sync Completed with Errors'
                    : 'Sync Skipped',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ),
            Chip(
              label: Text(
                record.triggerType == 'manual' ? 'Manual' : 'Scheduled',
                style: const TextStyle(fontSize: 12),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(formatSyncTimestamp(record.timestamp)),
            if (record.status == 'success' ||
                record.status == 'partial' ||
                record.status == 'failed') ...[
              const SizedBox(height: 4),
              Text(
                '${record.playlistsSynced} playlists • ${record.tracksDownloaded} tracks downloaded',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            // A partial/failed run carries its run-level summary in
            // errorMessage ("N of M playlists failed to sync"); the
            // per-playlist breakdown stays in the expanded section below.
            if (record.errorMessage != null &&
                (record.status == 'partial' || record.status == 'failed')) ...[
              const SizedBox(height: 4),
              Text(
                record.errorMessage!,
                style: TextStyle(fontSize: 12, color: Colors.red[700]),
              ),
            ],
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStat('Duration', _formatDuration(record.durationMs)),
                    _buildStat('Playlists', '${record.playlistsSynced}'),
                    _buildStat('Downloaded', '${record.tracksDownloaded}'),
                    if (record.tracksDeleted > 0)
                      _buildStat('Deleted', '${record.tracksDeleted}'),
                    // Since Phase 0.5 the worker records 0 rather than NULL
                    // when a sync uploads nothing; render that as "No events"
                    // instead of a bare 0/0.
                    if (record.playsSynced != null ||
                        record.skipsSynced != null) ...[
                      if (plays + skips > 0) ...[
                        _buildStat('Plays', '$plays'),
                        _buildStat('Skips', '$skips'),
                      ] else
                        _buildStat('Plays / Skips', 'No events'),
                    ],
                  ],
                ),

                // Error message if present
                if (record.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: Colors.red[700],
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Error:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    record.errorMessage!,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ],

                // Playlist details
                if (record.playlists != null &&
                    record.playlists!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Playlists:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...record.playlists!.map(
                    (playlist) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                playlist.errorMessage != null
                                    ? Icons.error_outline
                                    : Icons.queue_music,
                                size: 16,
                                color: playlist.errorMessage != null
                                    ? Colors.red[700]
                                    : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  playlist.playlistName,
                                  style: TextStyle(
                                    color: playlist.errorMessage != null
                                        ? Colors.red[700]
                                        : null,
                                  ),
                                ),
                              ),
                              Text(
                                '${playlist.tracksInPlaylist} tracks',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          if (playlist.errorMessage != null) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Text(
                                playlist.errorMessage!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red[600],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

/// History-row timestamp formatting, extracted from [HistoryScreen] as a
/// pure function (blockers.md 2026-10-17, "PMt" entry; invariant 50) so
/// the four branches can be pinned by test with an injected `now`.
///
/// The `at` literals are QUOTED inside the DateFormat patterns. A bare `a`
/// in a pattern is the AM/PM marker, so an unquoted `at` renders as
/// "PMt"/"AMt" — do not tidy the quotes back out (invariant 50).
String formatSyncTimestamp(int timestampMs, {DateTime? now}) {
  final now_ = now ?? DateTime.now();
  final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);

  // Create date-only versions (midnight of each day)
  final dateOnly = DateTime(date.year, date.month, date.day);
  final todayOnly = DateTime(now_.year, now_.month, now_.day);

  final daysDifference = todayOnly.difference(dateOnly).inDays;

  // Calculate actual time elapsed
  final elapsed = now_.difference(date);

  if (daysDifference == 0) {
    // Same calendar day - use relative time
    if (elapsed.inSeconds < 60) {
      return 'a few seconds ago';
    } else if (elapsed.inMinutes < 60) {
      final minutes = elapsed.inMinutes;
      return '$minutes minute${minutes == 1 ? '' : 's'} ago';
    } else {
      final hours = elapsed.inHours;
      return '$hours hour${hours == 1 ? '' : 's'} ago';
    }
  } else if (daysDifference == 1) {
    // Yesterday: "at" is a literal in the interpolated Dart string, which
    // is why this branch never mangled it.
    return 'Yesterday at ${DateFormat('h:mm a').format(date)}';
  } else if (daysDifference < 7 && _isInCurrentWeek(date, now_)) {
    // This week
    return DateFormat("EEEE 'at' h:mm a").format(date);
  } else {
    // Older (yyyy = the 4-digit year; 2-digit y gave "Oct 9, 26")
    return DateFormat("MMM d, yyyy 'at' h:mm a").format(date);
  }
}

bool _isInCurrentWeek(DateTime date, DateTime now) {
  // Find the start of the current week (most recent Sunday at midnight)
  final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
  final startOfWeekOnly = DateTime(
    startOfWeek.year,
    startOfWeek.month,
    startOfWeek.day,
  );

  // Check if date is on or after the start of this week
  final dateOnly = DateTime(date.year, date.month, date.day);
  return !dateOnly.isBefore(startOfWeekOnly);
}
