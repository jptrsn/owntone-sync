import 'package:flutter/material.dart';
import '../../data/repositories/local_database_repository.dart';
import '../../data/models/sync_history.dart';
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

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    // Create date-only versions (midnight of each day)
    final dateOnly = DateTime(date.year, date.month, date.day);
    final todayOnly = DateTime(now.year, now.month, now.day);

    final daysDifference = todayOnly.difference(dateOnly).inDays;

    // Calculate actual time elapsed
    final elapsed = now.difference(date);

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
      // Yesterday
      return 'Yesterday at ${DateFormat('h:mm a').format(date)}';
    } else if (daysDifference < 7 && _isInCurrentWeek(date, now)) {
      // This week
      return DateFormat('EEEE at h:mm a').format(date);
    } else {
      // Older
      return DateFormat('MMM d, y at h:mm a').format(date);
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'success':
        return Colors.green;
      case 'failed':
        return Colors.red;
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
    return Scaffold(
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
            Text(_formatTimestamp(record.timestamp)),
            if (record.status == 'success') ...[
              const SizedBox(height: 4),
              Text(
                '${record.playlistsSynced} playlists • ${record.tracksDownloaded} tracks downloaded',
                style: const TextStyle(fontSize: 12),
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
                      child: Row(
                        children: [
                          const Icon(Icons.queue_music, size: 16),
                          const SizedBox(width: 8),
                          Expanded(child: Text(playlist.playlistName)),
                          Text(
                            '${playlist.tracksInPlaylist} tracks',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
