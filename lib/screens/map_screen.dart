import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/firestore_utils.dart';
import '../widgets/disaster_alerts_widget.dart';

// 1. CONVERTED TO STATEFULWIDGET
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  bool _isLoading = true;
  final MapController _mapController = MapController();
  
  // Initial position (will be updated with user's location)
  static final LatLng _initialPosition = LatLng(12.9348, 79.1311);
  
  // List to hold markers
  final List<Marker> _markers = [];
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  bool _showOwmLayer = false;
  String _owmLayer = 'precipitation_new';

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _loadShelterPoints();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) return;
    final q = Uri.encodeQueryComponent(query.trim());
    final uri = Uri.parse('https://nominatim.openstreetmap.org/search?q=$q&format=json&limit=6');
    try {
      final resp = await http.get(uri, headers: {'User-Agent': 'survive_net_app'});
      if (resp.statusCode != 200) {
        setState(() => _searchResults = []);
        return;
      }
      final List<dynamic> body = jsonDecode(resp.body) as List<dynamic>;
      setState(() {
        _searchResults = body.map((e) => e as Map<String, dynamic>).toList();
      });
    } catch (e) {
      setState(() => _searchResults = []);
    }
  }

  void _selectSearchResult(Map<String, dynamic> r) {
    final lat = double.tryParse(r['lat']?.toString() ?? '');
    final lon = double.tryParse(r['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;
    // move map and add a search marker
    _mapController.move(LatLng(lat, lon), 15.0);
    setState(() {
      _markers.add(Marker(point: LatLng(lat, lon), width: 100, height: 80, child: Column(children: [Icon(Icons.place, color: Colors.purple, size: 30), Container(padding: const EdgeInsets.all(4), color: Colors.white, child: Text(r['display_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis))])));
      _searchResults = [];
      _searchController.text = r['display_name'] ?? '';
    });
  }

  // Request location permission and get current location
  Future<void> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled. Please enable them.')),
        );
      }
      return;
    }

    // Check location permission
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied.')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied. Please enable them in settings.'),
          ),
        );
      }
      return;
    }

    // Get current position
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _isLoading = false;
        
        // Add marker for current location
        _markers.add(
          Marker(
            point: LatLng(position.latitude, position.longitude),
            width: 80,
            height: 80,
            child: const Column(
              children: [
                Icon(Icons.my_location, color: Colors.blue, size: 30),
                Text(
                  'You',
                  style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      });

      // Move map to current location
      _mapController.move(
        LatLng(position.latitude, position.longitude),
        15.0,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  // 4. FUNCTION TO FETCH DATA AND CREATE MARKERS
  Future<void> _loadShelterPoints() async {
    final shelters = await FirestoreUtils.getShelters();
    
    // Clear existing markers and create new ones from the data
    _markers.clear();
    for (var shelter in shelters) {
      final name = shelter['name'] as String;
      final latitude = shelter['latitude'] as double;
      final longitude = shelter['longitude'] as double;
      final type = shelter['type'] as String;

      // Choose icon color based on shelter type
      Color markerColor;
      IconData markerIcon;
      switch (type) {
        case 'medical':
          markerColor = Colors.red;
          markerIcon = Icons.local_hospital;
          break;
        case 'food':
          markerColor = Colors.orange;
          markerIcon = Icons.restaurant;
          break;
        default: // emergency
          markerColor = Colors.green;
          markerIcon = Icons.house;
      }

      _markers.add(
        Marker(
          point: LatLng(latitude, longitude),
          width: 150,
          height: 80,
          child: Column(
            children: [
              Icon(markerIcon, color: markerColor, size: 30),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: markerColor),
                ),
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    color: markerColor,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Update the UI to show the new markers
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                // Search input
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: 'Search place (city, address)...',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () => _performSearch(_searchController.text),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (v) => _performSearch(v),
                      ),
                      if (_searchResults.isNotEmpty)
                        Container(
                          constraints: const BoxConstraints(maxHeight: 160),
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)]),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            itemBuilder: (context, i) {
                              final r = _searchResults[i];
                              return ListTile(
                                title: Text(r['display_name'] ?? r['name'] ?? ''),
                                onTap: () => _selectSearchResult(r),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  height: 350,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  margin: const EdgeInsets.only(bottom: 20, top: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _initialPosition,
                        initialZoom: 14.0,
                        interactionOptions: const InteractionOptions(
                          enableScrollWheel: true,
                          enableMultiFingerGestureRace: true,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.shalini.survive_net',
                        ),
                        if (_showOwmLayer)
                        Opacity(
                          opacity: 0.55,
                          child: TileLayer(
                            urlTemplate:
                                'https://tile.openweathermap.org/map/$_owmLayer/{z}/{x}/{y}.png?appid=YOUR_OPENWEATHERMAP_API_KEY',
                          ),
                        ),
                        MarkerLayer(
                          markers: _markers,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
                Positioned(
                  right: 10,
                  bottom: 30,
                  child: FloatingActionButton(
                    onPressed: _getCurrentLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
                // OpenWeather overlay toggle
                Positioned(
                  right: 10,
                  bottom: 100,
                  child: Column(
                    children: [
                      FloatingActionButton(
                        heroTag: 'owm_toggle',
                        mini: true,
                        onPressed: () {
                          setState(() => _showOwmLayer = !_showOwmLayer);
                        },
                        child: Icon(_showOwmLayer ? Icons.layers_clear : Icons.layers),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton(
                        heroTag: 'owm_cycle',
                        mini: true,
                        onPressed: () {
                          // cycle some common OWM layers
                          final layers = ['precipitation_new', 'clouds_new', 'wind_new', 'temp_new'];
                          final idx = layers.indexOf(_owmLayer);
                          final next = layers[(idx + 1) % layers.length];
                          setState(() => _owmLayer = next);
                        },
                        child: const Icon(Icons.repeat),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // --- The rest of your existing build method content ---
            
            // ... (Active Disasters Section and Safe Zones Section widgets follow here)
            
            const Text('Active Disasters',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: DisasterAlertsWidget(),
            ),
            
            const SizedBox(height: 20),

            // Safe Zones feature removed
          ],
        ),
      ),
    );
  }

  // Safe Zones feature removed — helper dialogs and CRUD operations have been deleted.
}