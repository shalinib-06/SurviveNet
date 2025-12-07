import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart'; // For real-time location

// --- Data Model for Weather Response ---
class WeatherData {
  final String location;
  final double temperature;
  final String description;
  final String icon;
  final int humidity;
  final double windSpeed;
  final int sunrise;
  final int sunset;

  WeatherData({
    required this.location,
    required this.temperature,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
    required this.sunrise,
    required this.sunset,
  });

  // Factory constructor updated for OpenWeatherMap's JSON structure
  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      location: json['name'] as String,
      // API provides temperature in Kelvin, converting to Celsius
      temperature: (json['main']['temp'] - 273.15) as double,
      description: json['weather'][0]['description'] as String,
      icon: json['weather'][0]['icon'] as String,
      humidity: (json['main']['humidity'] as num).toInt(),
      windSpeed: json['wind']['speed'] as double,
      sunrise: (json['sys']['sunrise'] as num).toInt(),
      sunset: (json['sys']['sunset'] as num).toInt(),
    );
  }
}

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  static const String apiKey = 'your_api_key_here'; // Replace with your OpenWeatherMap API key
  Future<WeatherData>? _weatherDataFuture;

  @override
  void initState() {
    super.initState();
    _weatherDataFuture = _fetchWeatherData();
  }

  // Helper function to get the current location
  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied. Please enable them in settings.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
    );
  }

  // --- Real API Fetch Logic (Fixed) ---
  Future<WeatherData> _fetchWeatherData() async {
    try {
      final position = await _getCurrentLocation();
      final lat = position.latitude;
      final lon = position.longitude;

      // Removed the redundant check since the API key is now provided.

      // OpenWeatherMap URL format:
      // 'https://api.openweathermap.org/data/2.5/weather?lat=[LAT]&lon=[LON]&appid=[KEY]'
      final url = 'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        return WeatherData.fromJson(data);
      } else {
        throw Exception('Failed to load weather data. Status code: ${response.statusCode}. Response: ${response.body}');
      }
    } catch (e) {
      throw Exception('Error fetching location or weather data: $e');
    }
  }

  // Helper function to map OpenWeatherMap API icons to Flutter Icons
  IconData _getWeatherIcon(String apiIconCode) {
    switch (apiIconCode.substring(0, 2)) {
      case '01': return Icons.wb_sunny_outlined; // Clear sky
      case '02': return Icons.cloud_outlined;    // Few clouds
      case '03': return Icons.cloud_circle_outlined; // Scattered clouds
      case '04': return Icons.cloud_queue_outlined; // Broken clouds
      case '09': return Icons.water_drop_outlined; // Shower rain
      case '10': return Icons.umbrella_outlined;  // Rain
      case '11': return Icons.thunderstorm_outlined; // Thunderstorm
      case '13': return Icons.ac_unit;         // Snow
      case '50': return Icons.waves_outlined;    // Mist
      default: return Icons.wb_sunny_outlined;
    }
  }

  // Helper function to convert Unix timestamp to time string
  String _formatTime(int unixTimestamp) {
    // OpenWeatherMap timestamps are in seconds
    final dateTime = DateTime.fromMillisecondsSinceEpoch(unixTimestamp * 1000, isUtc: true).toLocal();
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: false,
    );
  }

  // Widget for displaying main weather data
  Widget _buildCurrentWeather(WeatherData data) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on_outlined, size: 24, color: Colors.black87),
            const SizedBox(width: 8),
            Text(
              data.location,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Icon(
          _getWeatherIcon(data.icon),
          size: 100,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(height: 10),
        Text(
          '${data.temperature.toStringAsFixed(0)}°C',
          style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w100, color: Colors.black),
        ),
        Text(
          data.description.toUpperCase(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black54),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // Widget for displaying details (Wind, Humidity, Sunrise/Sunset)
  Widget _buildDetailCard({
    required IconData icon,
    required String label,
    required String value,
    required BuildContext context,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // Use theme card color (likely white)
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              spreadRadius: 1,
              blurRadius: 3,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: Theme.of(context).primaryColor),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () {
        setState(() {
          _weatherDataFuture = _fetchWeatherData();
        });
        return _weatherDataFuture!;
      },
      color: Theme.of(context).primaryColor,
      child: FutureBuilder<WeatherData>(
        future: _weatherDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor));
          } else if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _weatherDataFuture = _fetchWeatherData();
                        });
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          } else if (snapshot.hasData) {
            final data = snapshot.data!;
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh works
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                children: [
                  // --- Main Current Weather ---
                  _buildCurrentWeather(data),

                  // --- Details Row ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailCard(
                        icon: Icons.air_outlined,
                        label: 'Wind',
                        value: '${data.windSpeed.toStringAsFixed(1)} m/s', // Unit is m/s for OpenWeatherMap
                        context: context,
                      ),
                      _buildDetailCard(
                        icon: Icons.opacity_outlined,
                        label: 'Humidity',
                        value: '${data.humidity}%',
                        context: context,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailCard(
                        icon: Icons.wb_sunny_outlined,
                        label: 'Sunrise',
                        value: _formatTime(data.sunrise),
                        context: context,
                      ),
                      _buildDetailCard(
                        icon: Icons.nights_stay_outlined,
                        label: 'Sunset',
                        value: _formatTime(data.sunset),
                        context: context,
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'WEATHER FORECAST',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black.withOpacity(0.7),
                      ),
                    ),
                  ),
                  const Divider(height: 20),
                  // Mock Daily Forecast List (Replace with real data later)
                  _buildMockForecastItem('Today', 'Partly Cloudy', '25°/18°', Icons.wb_cloudy_outlined, context),
                  _buildMockForecastItem('Tomorrow', 'Sunny', '27°/19°', Icons.wb_sunny_outlined, context),
                  _buildMockForecastItem('Day 3', 'Light Rain', '23°/17°', Icons.umbrella_outlined, context),
                ],
              ),
            );
          } else {
            return const Center(child: Text('No weather data available.'));
          }
        },
      ),
    );
  }

  // Mock forecast list item (to be replaced with real forecast data from API)
  Widget _buildMockForecastItem(String day, String description, String temp, IconData icon, BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(day, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              Text(description, style: const TextStyle(fontSize: 14)),
            ],
          ),
          Text(temp, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
