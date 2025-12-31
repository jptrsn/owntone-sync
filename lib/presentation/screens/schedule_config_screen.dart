import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/sync_provider.dart';
import '../../data/models/sync_schedule.dart';

class ScheduleConfigScreen extends StatefulWidget {
  const ScheduleConfigScreen({super.key});

  @override
  State<ScheduleConfigScreen> createState() => _ScheduleConfigScreenState();
}

class _ScheduleConfigScreenState extends State<ScheduleConfigScreen> {
  late SyncSchedule _schedule;

  @override
  void initState() {
    super.initState();
    _schedule = context.read<SyncProvider>().syncSchedule;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Schedule'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
            },
          ),
          const Divider(),

          // Quick presets
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Quick Setup',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.nightlight),
            title: const Text('Overnight Sync'),
            subtitle: const Text('Every night at 2:00 AM'),
            trailing: _isOvernightPreset()
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              setState(() {
                _schedule = _schedule.copyWith(
                  enabled: true,
                  hour: 2,
                  minute: 0,
                  daysOfWeek: {1, 2, 3, 4, 5, 6, 7},
                  requiresCharging: true,
                  requiresWifi: true,
                );
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.work),
            title: const Text('Weekday Mornings'),
            subtitle: const Text('Mon-Fri at 6:00 AM'),
            trailing: _isWeekdayMorningPreset()
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              setState(() {
                _schedule = _schedule.copyWith(
                  enabled: true,
                  hour: 6,
                  minute: 0,
                  daysOfWeek: {1, 2, 3, 4, 5},
                  requiresCharging: true,
                  requiresWifi: true,
                );
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.weekend),
            title: const Text('Weekend Sync'),
            subtitle: const Text('Sat-Sun at 10:00 AM'),
            trailing: _isWeekendPreset()
                ? const Icon(Icons.check, color: Colors.green)
                : null,
            onTap: () {
              setState(() {
                _schedule = _schedule.copyWith(
                  enabled: true,
                  hour: 10,
                  minute: 0,
                  daysOfWeek: {6, 7},
                  requiresCharging: false,
                  requiresWifi: true,
                );
              });
            },
          ),

          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Custom Schedule',
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
                  'Note: Syncs may be delayed by up to 1 hour due to Android\'s battery optimization.',
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

  bool _isOvernightPreset() {
    return _schedule.hour == 2 &&
        _schedule.minute == 0 &&
        _schedule.daysOfWeek.length == 7 &&
        _schedule.requiresCharging &&
        _schedule.requiresWifi;
  }

  bool _isWeekdayMorningPreset() {
    return _schedule.hour == 6 &&
        _schedule.minute == 0 &&
        _schedule.daysOfWeek.length == 5 &&
        !_schedule.daysOfWeek.contains(6) &&
        !_schedule.daysOfWeek.contains(7);
  }

  bool _isWeekendPreset() {
    return _schedule.hour == 10 &&
        _schedule.minute == 0 &&
        _schedule.daysOfWeek.length == 2 &&
        _schedule.daysOfWeek.contains(6) &&
        _schedule.daysOfWeek.contains(7);
  }
}
