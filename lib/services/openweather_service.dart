import 'dart:convert';
import 'package:http/http.dart' as http;

class OwmAlert {
  final String senderName;
  final String event;
  final DateTime start;
  final DateTime end;
  final String description;
  final Map<String, dynamic>? tags;

  OwmAlert({
    required this.senderName,
    required this.event,
    required this.start,
    required this.end,
    required this.description,
    this.tags,
  });
}

class OpenWeatherService {
  static const String _apiKey = 'your_api_key_here'; // Replace with your OpenWeatherMap API key

  /// Fetch One Call alerts for given coordinates.
  /// Uses One Call 2.5 endpoint which is available on free tier for basic alerts.
  static Future<List<OwmAlert>> fetchAlerts(double lat, double lon) async {
    final uri = Uri.parse(
      'https://api.openweathermap.org/data/2.5/onecall?lat=$lat&lon=$lon&exclude=minutely,hourly,daily,current&appid=$_apiKey&units=metric',
    );

    try {
      final resp = await http.get(uri, headers: {'Accept': 'application/json'});
        if (resp.statusCode != 200) {
          // Log and return empty list instead of throwing to avoid fallback mock alerts
          // during normal operation when alerts are simply not present.
          // print for debugging; in production use a proper logger.
          print('OpenWeatherMap API returned ${resp.statusCode}: ${resp.body}');
          return <OwmAlert>[];
        }

        final Map<String, dynamic> body = json.decode(resp.body);
        final alertsJson = body['alerts'] as List<dynamic>?;
        if (alertsJson == null) return <OwmAlert>[];

      return alertsJson.map((a) {
        final startSec = (a['start'] ?? 0) as int;
        final endSec = (a['end'] ?? 0) as int;
        return OwmAlert(
          senderName: a['sender_name'] ?? 'Unknown',
          event: a['event'] ?? 'Unknown',
          start: DateTime.fromMillisecondsSinceEpoch(startSec * 1000),
          end: DateTime.fromMillisecondsSinceEpoch(endSec * 1000),
          description: a['description'] ?? '',
          tags: (a['tags'] is Map<String, dynamic>) ? a['tags'] as Map<String, dynamic> : null,
        );
      }).toList();
      } catch (e) {
        // Network or JSON parsing error. Log and return empty list so UI shows "no alerts"
        print('OpenWeatherService.fetchAlerts error: $e');
        return <OwmAlert>[];
      }
  }
}
