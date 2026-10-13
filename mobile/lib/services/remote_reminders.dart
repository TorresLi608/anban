import '../data/models.dart';
import '../data/planning.dart';

Map<String, dynamic> remoteReminderPlan(
  CareData data,
  DateTime now,
  String zone,
) {
  final enabled = data.settings['notifyRemote'] == 'true';
  return {
    'enabled': enabled,
    'timeZone': zone,
    'jobs': [
      if (enabled)
        for (final p in scheduleReminders(data, now, android: true))
          {
            'key': p.daily
                ? 'daily:${clockText(p.at)}'
                : '${p.channel}:${p.at.toUtc().millisecondsSinceEpoch}',
            'at': p.at.toUtc().toIso8601String(),
            'daily': p.daily ? clockText(p.at) : '',
          },
    ],
  };
}
