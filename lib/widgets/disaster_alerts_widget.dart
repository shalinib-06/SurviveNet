import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/openweather_service.dart';
// Intl removed because simple formatting is used to avoid an extra dependency at runtime

class DisasterAlertsWidget extends StatefulWidget {
  const DisasterAlertsWidget({super.key});

  @override
  State<DisasterAlertsWidget> createState() => _DisasterAlertsWidgetState();
}

class _UnifiedAlert {
  final String type;
  final String description;
  final DateTime timestamp;
  final String severity;
  final double? latitude;
  final double? longitude;
  final String source;

  _UnifiedAlert({
    required this.type,
    required this.description,
    required this.timestamp,
    required this.severity,
    this.latitude,
    this.longitude,
    required this.source,
  });
}

class _DisasterAlertsWidgetState extends State<DisasterAlertsWidget> {
  List<_UnifiedAlert> _alerts = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Always use OpenWeather alerts
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final owm = await OpenWeatherService.fetchAlerts(pos.latitude, pos.longitude);
      _alerts = owm
          .map((a) => _UnifiedAlert(
                type: a.event,
                description: a.description,
                timestamp: a.start,
                severity: 'Unknown',
                latitude: null,
                longitude: null,
                source: a.senderName.isNotEmpty ? 'OWM:${a.senderName}' : 'OpenWeather',
              ))
          .toList();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load alerts: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header with refresh
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [const Text('OpenWeather Alerts'), const Spacer(), IconButton(onPressed: _loadAlerts, icon: const Icon(Icons.refresh))]),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadAlerts, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_alerts.isEmpty) {
      return const Center(child: Text('No active alerts in your area', style: TextStyle(fontSize: 16)));
    }

    return RefreshIndicator(
      onRefresh: _loadAlerts,
      child: ListView.builder(
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          final alert = _alerts[index];
          final color = _severityColor(alert.severity);
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(_alertIcon(alert.type), color: color),
              ),
              title: Text(alert.type, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(alert.description),
                  const SizedBox(height: 4),
                      Text('${alert.source} • ${_formatDate(alert.timestamp)}', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ],
              ),
              isThreeLine: true,
              onTap: () => _showDetails(alert),
            ),
          );
        },
      ),
    );
  }

  Color _severityColor(String s) {
    final v = s.toLowerCase();
    if (v.contains('severe') || v.contains('high')) return Colors.red;
    if (v.contains('moderate') || v.contains('medium')) return Colors.orange;
    if (v.contains('minor') || v.contains('low')) return Colors.yellow.shade700;
    return Colors.blue;
  }

  IconData _alertIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('cyclone') || t.contains('storm')) return Icons.public;
    if (t.contains('flood') || t.contains('rain')) return Icons.water;
    if (t.contains('earthquake')) return Icons.vibration;
    if (t.contains('thunder')) return Icons.flash_on;
    return Icons.warning;
  }

  void _showDetails(_UnifiedAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(children: [Icon(_alertIcon(alert.type), color: _severityColor(alert.severity)), const SizedBox(width: 8), Text(alert.type)]),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(alert.description),
            const SizedBox(height: 16),
            Text('Severity: ${alert.severity}', style: TextStyle(color: _severityColor(alert.severity))),
            const SizedBox(height: 8),
                Text('Time: ${_formatDate(alert.timestamp, includeYear: true)}'),
            if (alert.latitude != null && alert.longitude != null) ...[
              const SizedBox(height: 8),
              Text('Location: ${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}'),
            ],
            const SizedBox(height: 8),
            Text('Source: ${alert.source}'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  String _formatDate(DateTime dt, {bool includeYear = false}) {
    final d = dt.toLocal();
    final month = d.month;
    final day = d.day;
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    if (includeYear) {
      return '$month/$day/${d.year} $hour:$minute $ampm';
    }
    return '$month/$day $hour:$minute $ampm';
  }
}