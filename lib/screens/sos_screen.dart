import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

// Global variables provided by the Canvas environment for Firebase setup.
const String __app_id = "survivenet";

// --- Emergency Contact Data Model ---
class EmergencyContact {
  final String id;
  final String name;
  final String number;
  EmergencyContact({required this.id, required this.name, required this.number});
}

// Custom Dialog/Modal to replace alert() and confirm()
Future<void> _showAppDialog(BuildContext context, String title, String content, {bool isError = false}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title, style: TextStyle(color: isError ? Colors.red : Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            child: const Text('OK'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  // State variables for Location
  String _location = 'Initializing services...';
  // NEW: Variables to store raw coordinates and the map link
  double _currentLat = 0.0; 
  double _currentLon = 0.0;
  String _locationLink = 'No link available'; // Stores the generated Google Maps URL
  
  DateTime _lastUpdate = DateTime.now();
  Timer? _locationTimer;
  StreamSubscription? _contactsSubscription;
  StreamSubscription? _authStateSubscription;

  // State variables for Contacts and Firebase
  String? _userId;
  List<EmergencyContact> _emergencyContacts = [];
  bool _isLoading = true;
  final String _emergencyNumber = '100'; // Target emergency number
  // Battery reporting removed per user request

  @override
  void initState() {
    super.initState();
    _initFirebaseAndContacts();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _contactsSubscription?.cancel();
    _authStateSubscription?.cancel();
    super.dispose();
  }

  // --- 1. Firebase/Auth/Contact Setup ---

  Future<void> _initFirebaseAndContacts() async {
    if (!mounted) return;
    
    final auth = FirebaseAuth.instance;
    
    setState(() {
      _isLoading = true;
    });

    _authStateSubscription = auth.authStateChanges().listen((User? user) {
      if (mounted) {
        if (user != null) {
          setState(() {
            _userId = user.uid;
            _isLoading = false;
          });
          if (_userId != null) { 
             _fetchEmergencyContacts();
          }
        } else {
          setState(() {
            _userId = null;
            _emergencyContacts = [];
            _isLoading = false;
          });
        }
      }
    });
  }

  // Set up real-time listener for emergency contacts from Firestore
  void _fetchEmergencyContacts() {
    if (_userId == null) return;
    
    _contactsSubscription?.cancel();

    final db = FirebaseFirestore.instance;
    final collectionPath = 'artifacts/$__app_id/users/$_userId/emergency_contacts';
    
    _contactsSubscription = db.collection(collectionPath)
      .snapshots()
      .listen((snapshot) {
        if (mounted) {
          final contacts = snapshot.docs.map((doc) {
              final data = doc.data();
              return EmergencyContact(
                id: doc.id,
                name: data['name'] ?? 'Unknown',
                number: data['number'] ?? 'N/A',
              );
            }).toList();
          
          contacts.sort((a, b) => a.name.compareTo(b.name));
          
          setState(() {
            _emergencyContacts = contacts;
          });
        }
      }, onError: (e) {
        print("Error listening to contacts: $e");
        if (_userId != null) {
          _showAppDialog(context, 'Firestore Error', 'Failed to load emergency contacts.', isError: true);
        }
      });
  }
  
  // New unified method to handle adding a contact
  Future<void> _addEmergencyContact(EmergencyContact contact) async {
    if (_userId == null) {
      _showAppDialog(context, 'Auth Required', 'Cannot save contact: User not authenticated.');
      return;
    }
    
    final cleanNumber = contact.number.replaceAll(RegExp(r'[^0-9\+]'), '');

    if (cleanNumber.isEmpty) {
      _showAppDialog(context, 'Invalid Number', 'The selected contact has no valid phone number.');
      return;
    }

    try {
      final db = FirebaseFirestore.instance;
      final collectionPath = 'artifacts/$__app_id/users/$_userId/emergency_contacts';
      
      await db.collection(collectionPath).doc(cleanNumber).set({
        'name': contact.name,
        'number': cleanNumber,
        'addedAt': FieldValue.serverTimestamp(),
      });
      _showAppDialog(context, 'Contact Added', '${contact.name} (${cleanNumber}) has been added as an emergency contact.');
      
    } catch (e) {
      print('Failed to add contact: $e');
       _showAppDialog(context, 'Error Saving', 'Failed to save contact: ${e.toString()}', isError: true);
    }
  }


  Future<void> _removeEmergencyContact(String contactId, String name) async {
    if (_userId == null) return;
    
    final bool? shouldRemove = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Removal'),
          content: Text('Are you sure you want to remove $name from emergency contacts?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );

    if (shouldRemove == true) {
      try {
        final db = FirebaseFirestore.instance;
        final collectionPath = 'artifacts/$__app_id/users/$_userId/emergency_contacts';
        await db.collection(collectionPath).doc(contactId).delete();
        _showAppDialog(context, 'Contact Removed', '$name has been removed from your emergency contacts.');
      } catch (e) {
        print('Failed to remove contact: $e');
         _showAppDialog(context, 'Error Deleting', 'Failed to remove contact: ${e.toString()}', isError: true);
      }
    }
  }

  // --- 2. Location Logic ---

  // Starts a timer to update location every 5 seconds
  void _startLocationUpdates() {
    _fetchLiveLocation(); // Initial fetch
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (Timer t) => _fetchLiveLocation());
  }

  Future<void> _fetchLiveLocation() async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() { 
          _location = 'Location permission denied'; 
          _locationLink = 'No link available due to permissions.';
          _currentLat = 0.0;
          _currentLon = 0.0;
        });
        }
        return;
      }

      // Get current position
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      final lat = pos.latitude;
      final lon = pos.longitude;

      // 1. Construct the Google Maps link (for search query)
      final mapLink = 'https://www.google.com/maps/search/?api=1&query=$lat,$lon';

      // 2. Reverse geocode to a human-readable placemark/address
      String address = 'Lat: ${lat.toStringAsFixed(5)}, Lon: ${lon.toStringAsFixed(5)}';
      try {
        final placemarks = await placemarkFromCoordinates(lat, lon);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
      final parts = [p.subThoroughfare, p.thoroughfare, p.locality, p.subAdministrativeArea, p.administrativeArea, p.country]
        .where((s) => s != null && s.isNotEmpty)
        .toList();
          if (parts.isNotEmpty) address = parts.join(', ');
        }
      } catch (e) {
        print('Reverse geocoding failed: $e');
      }

      if (mounted) {
        setState(() {
          _location = address;
          _currentLat = lat; // Store raw coordinates
          _currentLon = lon;
          _locationLink = mapLink; // Store the link
          _lastUpdate = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _location = 'Location access denied or failed.';
          _locationLink = 'Location failed to acquire.';
          _currentLat = 0.0;
          _currentLon = 0.0;
        });
      }
    }
  }

  // --- 3. SOS Call Logic (Updated for Direct Dial/Send Screen) ---

  Future<void> _callEmergency(String number) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Initiate SOS?'),
          content: Text('This will open the dialer for $number and pre-fill SMS messages for your saved contacts. You must press "Call" and "Send" manually.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Send', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    
    try {
      // 1. Get the most recent location
      await _fetchLiveLocation();
      
      String message;
      if (_locationLink.contains('google.com')) {
        // Use the detailed message including the clickable link
        message = '''EMERGENCY(From SuriveNet): I am in danger and need help immediately.

My location: $_location
Lat/Lon: ${_currentLat.toStringAsFixed(5)}, ${_currentLon.toStringAsFixed(5)}
***Click for Map: $_locationLink***

Please conatct emergency services or send help quickly.
Note: I might not be able to return your call.''';
      } else {
        // Fallback message if location failed
        message = 'EMERGENCY: I need help. Location details are currently unavailable. Please conatct emergency services or send help quickly.';
      }

      // Battery info removed; use the message as-is
      final messageWithBattery = message;

      // 3. Launch SMS to all contacts in a single composer when supported (comma-separated recipients)
      if (_emergencyContacts.isNotEmpty) {
        try {
          final recipients = _emergencyContacts.map((c) => c.number).join(',');
          final smsUri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(messageWithBattery)}');
          await launchUrl(smsUri, mode: LaunchMode.externalNonBrowserApplication);
        } catch (e) {
          print('Failed to launch group SMS composer, falling back to individual SMS: $e');
          // Fallback to individual SMS when group composer isn't supported
          for (final contact in _emergencyContacts) {
            try {
              final smsUri = Uri.parse('sms:${contact.number}?body=${Uri.encodeComponent(messageWithBattery)}');
              await launchUrl(smsUri, mode: LaunchMode.externalNonBrowserApplication);
              await Future.delayed(const Duration(milliseconds: 300));
            } catch (e2) {
              print('Failed to launch SMS for ${contact.number}: $e2');
            }
          }
        }
      }

      // 3. Launch the main emergency call
      final callUri = Uri.parse('tel:$number');
      if (await canLaunchUrl(callUri)) {
        await launchUrl(callUri, mode: LaunchMode.externalNonBrowserApplication);
      } else {
        _showAppDialog(context, 'Error', 'Could not initiate call to $number.', isError: true);
        return;
      }
      
      // 4. Notify user in-app
      _showAppDialog(context, 'SOS Actions Initiated!', 'The emergency call and SMS screens have been opened. Please tap **Call** and **Send** to complete the alert process. The SMS includes a **Google Maps link** for quick tracking.');
      
    } catch (e) {
      print('Error during SOS flow: $e');
      _showAppDialog(context, 'Error', 'Failed to perform SOS actions: ${e.toString()}', isError: true);
    }
  }

  // --- 4. UI Helper Functions ---

  // Sends an SMS (group composer where possible) to all emergency contacts with given body
  Future<void> _sendSmsToAll(String body) async {
    if (_emergencyContacts.isEmpty) {
      _showAppDialog(context, 'No Emergency Contacts', 'You do not have any emergency contacts configured. Use Add Contact to add friends or family.');
      return;
    }

    final recipients = _emergencyContacts.map((c) => c.number).join(',');
    try {
      final smsUri = Uri.parse('sms:$recipients?body=${Uri.encodeComponent(body)}');
      await launchUrl(smsUri, mode: LaunchMode.externalNonBrowserApplication);
    } catch (e) {
      // Fallback: try sending to each contact individually
      for (final contact in _emergencyContacts) {
        try {
          final smsUri = Uri.parse('sms:${contact.number}?body=${Uri.encodeComponent(body)}');
          await launchUrl(smsUri, mode: LaunchMode.externalNonBrowserApplication);
          await Future.delayed(const Duration(milliseconds: 300));
        } catch (_) {
          // ignore per-contact failures
        }
      }
    }
  }

  // Build and send a location-only SMS to all emergency contacts
  Future<void> _sendLocationToAll() async {
    try {
      await _fetchLiveLocation();

      final String message = '''LOCATION ALERT (From SurviveNet):\nI need assistance.\n\nLocation: $_location\nMap: $_locationLink\nLat/Lon: ${_currentLat.toStringAsFixed(5)}, ${_currentLon.toStringAsFixed(5)}''';

      await _sendSmsToAll(message);
      _showAppDialog(context, 'Location Sent', 'Location SMS composer opened for your emergency contacts. Please press Send in your messaging app.');
    } catch (e) {
      print('Failed to send location to all: $e');
      _showAppDialog(context, 'Error', 'Failed to prepare location SMS: ${e.toString()}', isError: true);
    }
  }

  // Build and send a medical alert SMS to all emergency contacts
  Future<void> _sendMedicalAlertToAll() async {
    try {
      await _fetchLiveLocation();

      final String message = '''MEDICAL EMERGENCY (From SurviveNet):\nI require urgent medical assistance.\n\nLocation: $_location\nMap: $_locationLink\nLat/Lon: ${_currentLat.toStringAsFixed(5)}, ${_currentLon.toStringAsFixed(5)}\n\nPlease send help immediately.''';

      await _sendSmsToAll(message);
      _showAppDialog(context, 'Medical Alert Prepared', 'Medical alert SMS composer opened for your emergency contacts. Please press Send in your messaging app.');
    } catch (e) {
      print('Failed to send medical alert to all: $e');
      _showAppDialog(context, 'Error', 'Failed to prepare medical alert SMS: ${e.toString()}', isError: true);
    }
  }

  // Opens the native contact picker
  Future<void> _pickContactFromDevice() async {
    if (_userId == null) {
      _showAppDialog(context, 'Auth Required', 'You must be logged in to add contacts.');
      return;
    }
    
    try {
      if (!await FlutterContacts.requestPermission()) {
        _showAppDialog(context, 'Permission Denied', 'Contacts permission is required to select a contact.');
        return;
      }
      
      final Contact? contact = await FlutterContacts.openExternalPick();

      if (contact == null) {
        return;
      }
      
      final name = contact.displayName.isNotEmpty 
          ? contact.displayName 
          : 'Unknown Contact';
      
      final phone = contact.phones.isNotEmpty
          ? contact.phones.first.number
          : null;

      if (phone == null || phone.isEmpty) {
        _showAppDialog(context, 'No Number', 'The selected contact (${name}) does not have a registered phone number.');
        return;
      }
      
      final newContact = EmergencyContact(
        id: phone.replaceAll(RegExp(r'[^0-9\+]'), ''), // Use cleaned number as ID
        name: name,
        number: phone,
      );
      
      await _addEmergencyContact(newContact);

    } catch (e) {
      print('Error picking contact: $e');
      _showAppDialog(context, 'Contact Error', 'Failed to pick contact from device: ${e.toString()}', isError: true);
    }
  }

  Widget _buildContactTile(EmergencyContact contact, IconData icon) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.grey.shade700),
      title: Text(contact.name),
      subtitle: Text(contact.number, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.call, color: Colors.green),
            onPressed: () => _callEmergency(contact.number),
            tooltip: 'Call ${contact.name}',
          ),
          if (contact.id != '108' && contact.id != '112' && contact.id != '101') 
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _removeEmergencyContact(contact.id, contact.name),
            tooltip: 'Remove Contact',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking user session...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lens_sharp, color: Theme.of(context).primaryColor, size: 24),
            const SizedBox(width: 4),
            const Text(
              'SurviveNet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Emergency SOS',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const Text(
                'Tap the button below to send emergency alert',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),

              // SOS Button
              Center(
                child: InkWell(
                  onTap: () => _callEmergency(_emergencyNumber),
                  child: Container(
                    width: 150,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.5),
                          spreadRadius: 8,
                          blurRadius: 15,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.phone, color: Colors.white, size: 50),
                        Text(
                          'SOS - $_emergencyNumber',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Your Location Card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.location_on, color: Colors.black),
                          SizedBox(width: 8),
                          Text('Your Live Location',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(_location,
                          style: const TextStyle(
                              color: Colors.black87,
                              fontWeight: FontWeight.w500)),
                      Text(
                          'Map Link: ${_locationLink.contains('google.com') ? 'Ready' : 'Unavailable'}',
                          style: TextStyle(color: _locationLink.contains('google.com') ? Colors.green : Colors.orange, fontWeight: FontWeight.w500)
                      ),
                      Text(
                          'Last updated: ${_lastUpdate.hour.toString().padLeft(2, '0')}:${_lastUpdate.minute.toString().padLeft(2, '0')}:${_lastUpdate.second.toString().padLeft(2, '0')} (Every 5s)',
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Emergency Contacts Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Emergency Contacts',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    icon: const Icon(Icons.person_add, color: Colors.black),
                    label: const Text('Add Contact',
                        style: TextStyle(color: Colors.black)),
                    onPressed: _pickContactFromDevice,
                    style:
                        TextButton.styleFrom(backgroundColor: Colors.transparent),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Emergency Contacts List from Firestore
              if (_userId == null)
                const Center(child: Text('Please log in to manage your contacts.', style: TextStyle(color: Colors.grey)))
              else if (_emergencyContacts.isEmpty)
                const Center(child: Padding(
                  padding: EdgeInsets.only(top: 10.0),
                  child: Text('No custom contacts added. Use "Add Contact" to select a friend or family member from your device.', style: TextStyle(color: Colors.grey)),
                ))
              else
                ..._emergencyContacts.map((contact) => _buildContactTile(contact, Icons.person_pin)),
              
              const Divider(height: 20),

              // Default Emergency Services List (Static)
              Text('Default Services', style: TextStyle(fontSize: 14, color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
              _buildContactTile(EmergencyContact(id: '108', name: 'Ambulance', number: '108'), Icons.local_hospital),
              _buildContactTile(EmergencyContact(id: '112', name: 'National Emergency Helpline', number: '112'), Icons.local_police),
              _buildContactTile(EmergencyContact(id: '101', name: 'Fire Department', number: '101'), Icons.local_fire_department),
            ],
          ),
        ),
      ),
      // Quick Actions bar at the bottom for rapid alerts
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendLocationToAll,
                  icon: const Icon(Icons.my_location_outlined, color: Colors.white),
                  label: const Text('Send Location'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _sendMedicalAlertToAll,
                  icon: const Icon(Icons.medical_services_outlined, color: Colors.white),
                  label: const Text('Medical Alert'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
