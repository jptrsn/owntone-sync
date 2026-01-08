import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../../data/models/sync_schedule.dart';

class ScheduleConfigScreen extends StatefulWidget {
  const ScheduleConfigScreen({super.key});

  @override
  State<ScheduleConfigScreen> createState() => _ScheduleConfigScreenState();
}

class _ScheduleConfigScreenState extends State<ScheduleConfigScreen>
    with WidgetsBindingObserver {
  late SyncSchedule _schedule;

  @override
  void initState() {
    super.initState();
    _schedule = context.read<SyncProvider>().syncSchedule;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check battery optimization when returning to app
      context.read<SyncProvider>().checkBatteryOptimization();
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _schedule.hour, minute: _schedule.minute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _schedule = _schedule.copyWith(
          hour: picked.hour,
          minute: picked.minute,
        );
      });
    }
  }

  Future<void> _checkAndPromptBatteryOptimization() async {
    final provider = context.read<SyncProvider>();
    await provider.checkBatteryOptimization();

    if (!provider.isBatteryOptimizationDisabled && mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Battery Optimization'),
          content: const Text(
            'For reliable scheduled syncs, disable battery optimization for this app. '
            'Otherwise, Android may skip or delay syncs to save battery, even if your battery is charging.\n\n'
            'This is especially important for overnight syncs when your device is idle.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await provider.requestBatteryOptimizationExemption();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Schedule'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Enable Automatic Sync'),
            subtitle: Text(_schedule.getScheduleDescription()),
            value: _schedule.enabled,
            onChanged: (value) {
              setState(() {
                _schedule = _schedule.copyWith(enabled: value);
              });
              if (value) {
                _checkAndPromptBatteryOptimization();
              }
            },
          ),
          Consumer<SyncProvider>(
            builder: (context, provider, child) {
              if (_schedule.enabled &&
                  !provider.isBatteryOptimizationDisabled) {
                return Container(
                  color: Colors.orange.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Battery optimization is enabled. Tap Fix to open settings and select "Don\'t optimize" for this app.',
                          style: TextStyle(color: Colors.orange.shade900),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            provider.requestBatteryOptimizationExemption(),
                        child: const Text('Fix'),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Consumer<SyncProvider>(
            builder: (context, provider, child) {
              if (provider.missedSyncTime != null) {
                final missed = provider.missedSyncTime!;
                final formatted =
                    '${missed.day}/${missed.month} at ${missed.hour.toString().padLeft(2, '0')}:${missed.minute.toString().padLeft(2, '0')}';
                return Container(
                  color: Colors.red.shade100,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Scheduled sync at $formatted may have been skipped. Check battery settings.',
                          style: TextStyle(color: Colors.red.shade900),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: Colors.red.shade700,
                        onPressed: () => provider.dismissMissedSyncWarning(),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Synchronization Schedule',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),

          ListTile(
            leading: const Icon(Icons.access_time),
            title: const Text('Time'),
            subtitle: Text(
              '${_schedule.hour.toString().padLeft(2, '0')}:${_schedule.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _schedule.enabled ? _selectTime : null,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Days of Week',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Wrap(
              spacing: 8,
              children: [
                _buildDayChip('Mon', 1),
                _buildDayChip('Tue', 2),
                _buildDayChip('Wed', 3),
                _buildDayChip('Thu', 4),
                _buildDayChip('Fri', 5),
                _buildDayChip('Sat', 6),
                _buildDayChip('Sun', 7),
              ],
            ),
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Conditions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_charging_full),
            title: const Text('Only when charging'),
            subtitle: const Text('Device must be plugged in'),
            value: _schedule.requiresCharging,
            onChanged: _schedule.enabled
                ? (value) {
                    setState(() {
                      _schedule = _schedule.copyWith(requiresCharging: value);
                    });
                  }
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: const Text('Only on WiFi'),
            subtitle: const Text('Avoid mobile data usage'),
            value: _schedule.requiresWifi,
            onChanged: _schedule.enabled
                ? (value) {
                    setState(() {
                      _schedule = _schedule.copyWith(requiresWifi: value);
                    });
                  }
                : null,
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    await context.read<SyncProvider>().updateSyncSchedule(
                      _schedule,
                    );
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _schedule.enabled
                                ? 'Schedule saved: ${_schedule.getScheduleDescription()}'
                                : 'Automatic sync disabled',
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Save Schedule'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Note: Background syncs are subject to Android battery optimization and may be delayed. '
                  'On Android 12+, syncs typically run within a 1-hour window of the scheduled time when '
                  'charging/WiFi conditions are met.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayChip(String label, int day) {
    final isSelected = _schedule.daysOfWeek.contains(day);
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: _schedule.enabled
          ? (selected) {
              setState(() {
                final newDays = Set<int>.from(_schedule.daysOfWeek);
                if (selected) {
                  newDays.add(day);
                } else {
                  newDays.remove(day);
                }
                // Ensure at least one day is selected
                if (newDays.isNotEmpty) {
                  _schedule = _schedule.copyWith(daysOfWeek: newDays);
                }
              });
            }
          : null,
    );
  }
}
