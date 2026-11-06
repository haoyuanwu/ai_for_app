/// Recover legacy messages without a timestamp and persist a stable reference
/// so retries cannot move relative dates to a different day.
DateTime ensureMessageTime(Map<String, dynamic> message, DateTime now) {
  final raw = message['time'];
  final parsed = raw is String ? DateTime.tryParse(raw) : null;
  if (parsed != null) return parsed.toLocal();
  message['time'] = now.toIso8601String();
  return now.toLocal();
}
