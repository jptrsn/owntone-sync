class SyncState {
  final bool isRunning;
  final DateTime? lastSyncTime;
  final bool lastSyncSuccess;

  SyncState({
    this.isRunning = false,
    this.lastSyncTime,
    this.lastSyncSuccess = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'isRunning': isRunning,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'lastSyncSuccess': lastSyncSuccess,
    };
  }

  factory SyncState.fromJson(Map<String, dynamic> json) {
    return SyncState(
      isRunning: json['isRunning'] ?? false,
      lastSyncTime: json['lastSyncTime'] != null
          ? DateTime.parse(json['lastSyncTime'])
          : null,
      lastSyncSuccess: json['lastSyncSuccess'] ?? false,
    );
  }
}
