import '../../data/models/sync_state.dart';

class SyncSchedule {
  final bool enabled;
  final ScheduleType scheduleType;

  // For daily schedules
  final int hour; // 0-23
  final int minute; // 0-59

  // For weekly schedules
  final Set<int> daysOfWeek; // 1=Monday, 7=Sunday

  // Conditions
  final bool requiresCharging;
  final bool requiresWifi;

  SyncSchedule({
    this.enabled = false,
    this.scheduleType = ScheduleType.daily,
    this.hour = 2, // 2 AM default
    this.minute = 0,
    this.daysOfWeek = const {1, 2, 3, 4, 5, 6, 7}, // All days
    this.requiresCharging = true,
    this.requiresWifi = true,
  });

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'scheduleType': scheduleType.toString(),
      'hour': hour,
      'minute': minute,
      'daysOfWeek': daysOfWeek.toList(),
      'requiresCharging': requiresCharging,
      'requiresWifi': requiresWifi,
    };
  }

  factory SyncSchedule.fromJson(Map<String, dynamic> json) {
    return SyncSchedule(
      enabled: json['enabled'] ?? false,
      scheduleType: ScheduleType.values.firstWhere(
        (e) => e.toString() == json['scheduleType'],
        orElse: () => ScheduleType.daily,
      ),
      hour: json['hour'] ?? 2,
      minute: json['minute'] ?? 0,
      daysOfWeek:
          (json['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toSet() ??
          {1, 2, 3, 4, 5, 6, 7},
      requiresCharging: json['requiresCharging'] ?? true,
      requiresWifi: json['requiresWifi'] ?? true,
    );
  }

  SyncSchedule copyWith({
    bool? enabled,
    ScheduleType? scheduleType,
    int? hour,
    int? minute,
    Set<int>? daysOfWeek,
    bool? requiresCharging,
    bool? requiresWifi,
  }) {
    return SyncSchedule(
      enabled: enabled ?? this.enabled,
      scheduleType: scheduleType ?? this.scheduleType,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      requiresCharging: requiresCharging ?? this.requiresCharging,
      requiresWifi: requiresWifi ?? this.requiresWifi,
    );
  }

  /// Check if current time matches this schedule and we haven't already synced
  bool shouldSyncNow(DateTime now, SyncState syncState) {
    if (!enabled) return false;

    // Don't sync if one is already running
    if (syncState.isRunning) {
      return false;
    }

    // Check day of week
    final dayOfWeek = now.weekday; // 1=Monday, 7=Sunday
    if (!daysOfWeek.contains(dayOfWeek)) return false;

    // Calculate scheduled time for today
    final scheduledTime = DateTime(now.year, now.month, now.day, hour, minute);

    // Check if we're within the sync window (scheduled time to scheduled time + 15 minutes)
    // This matches our 15-minute WorkManager check interval
    final isInWindow =
        now.isAfter(scheduledTime) &&
        now.isBefore(scheduledTime.add(const Duration(hours: 1)));

    if (!isInWindow) return false;

    // If we're in the window, check if we already synced for this scheduled time
    if (syncState.lastSyncTime != null && syncState.lastSyncSuccess) {
      // Check if last sync was for this same scheduled slot
      final lastSyncScheduledTime = DateTime(
        syncState.lastSyncTime!.year,
        syncState.lastSyncTime!.month,
        syncState.lastSyncTime!.day,
        hour,
        minute,
      );

      // If last successful sync was for today's scheduled time, don't sync again
      if (syncState.lastSyncTime!.isAfter(lastSyncScheduledTime) &&
          syncState.lastSyncTime!.isBefore(
            lastSyncScheduledTime.add(const Duration(hours: 1)),
          )) {
        return false;
      }
    }

    return true;
  }

  String getScheduleDescription() {
    if (!enabled) return 'Disabled';

    final timeStr =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

    if (scheduleType == ScheduleType.daily) {
      if (daysOfWeek.length == 7) {
        return 'Daily at $timeStr';
      } else if (daysOfWeek.length == 5 &&
          !daysOfWeek.contains(6) &&
          !daysOfWeek.contains(7)) {
        return 'Weekdays at $timeStr';
      } else if (daysOfWeek.length == 2 &&
          daysOfWeek.contains(6) &&
          daysOfWeek.contains(7)) {
        return 'Weekends at $timeStr';
      } else {
        final days = daysOfWeek.toList()..sort();
        final dayNames = days.map(_getDayName).join(', ');
        return '$dayNames at $timeStr';
      }
    }

    return 'Custom schedule';
  }

  String _getDayName(int day) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[day - 1];
  }
}

enum ScheduleType { daily, custom }
