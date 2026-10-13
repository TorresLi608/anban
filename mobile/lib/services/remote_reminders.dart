import '../data/models.dart';
import '../data/planning.dart';

Map<String, dynamic> remoteReminderPlan(
  CareData data,
  DateTime now,
  String zone,
) {
  final enabled = data.settings['notifyRemote'] == 'true';
  final jobs = <String, Map<String, dynamic>>{};
  if (enabled) {
    for (final p in scheduleReminders(data, now, android: true)) {
      final key = p.daily
          ? 'daily:${clockText(p.at)}'
          : 'event:${p.at.toUtc().millisecondsSinceEpoch}';
      jobs[key] = {
        'key': key,
        'at': p.at.toUtc().toIso8601String(),
        'daily': p.daily ? clockText(p.at) : '',
      };
    }
  }
  return {'enabled': enabled, 'timeZone': zone, 'jobs': jobs.values.toList()};
}
