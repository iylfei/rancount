import 'package:timezone/timezone.dart' as tz;

// Accounting dates use UTC+08 throughout, independent of the device time zone.
final _beijing = tz.Location('Asia/Shanghai', [], [], [
  tz.TimeZone(8 * Duration.millisecondsPerHour,
      isDst: false, abbreviation: 'CST'),
]);

DateTime beijingTime(DateTime instant) => tz.TZDateTime.from(instant, _beijing);
DateTime beijingNow() => beijingTime(DateTime.now());
DateTime beijingDate(int year, int month,
        [int day = 1, int hour = 0, int minute = 0, int second = 0]) =>
    tz.TZDateTime(_beijing, year, month, day, hour, minute, second);
