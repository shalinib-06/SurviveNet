// ignore_for_file: unused_field, avoid_print, constant_identifier_names, unnecessary_to_list_in_spreads, unnecessary_brace_in_string_interps, prefer_final_fields

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- Global Firebase Variable Access (Mandatory for Firestore) ---
// We ignore the constant_identifier_names lint for these global variables
// as they are required by the environment.
const String __app_id = 'survivenet';
const String __initial_auth_token = '';

class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  // Emergency kit items and checked state
  final List<String> _kitItems = const [
    'Emergency water (1 gallon per person per day)',
    'Non-perishable food (3-day supply)',
    'Battery-powered or hand crank radio',
    'Flashlight and extra batteries',
    'First aid kit',
    'Whistle for signaling help',
    'Local maps',
    'Cell phone with chargers and backup battery',
  ];

  // Map to hold item name -> checked status (from Firestore)
  // Changed to final to satisfy prefer_final_fields lint
  final Map<String, bool> _kitChecked = {};

  // Firebase instances
  late final FirebaseFirestore _db;
  late final FirebaseAuth _auth;
  String _userId = 'default-user-id';
  bool _isLoading = true;

  // Disaster guides structured data
  late final Map<String, Map<String, dynamic>> _disasterGuides;

  @override
  void initState() {
    super.initState();
    _initializeFirebaseAndLoadData();

    // Initialize checklist map structure locally
    for (var item in _kitItems) {
      _kitChecked[item] = false;
    }

    _disasterGuides = {
      'earthquake': {
        'title': 'Earthquake Safety',
        'icon': Icons.house,
        'before': [
          'Secure heavy furniture and appliances to walls',
          'Create a family communication and evacuation plan',
          'Keep emergency supplies (water, food, flashlight) accessible',
          'Know how to turn off gas and utilities if needed',
        ],
        'during': [
          'Drop, Cover, and Hold On — protect your head and neck',
          'Stay indoors away from windows and heavy objects',
          'If outdoors, move to an open area away from buildings and trees',
          'If driving, pull over safely and stop until shaking stops',
        ],
        'after': [
          'Check yourself and others for injuries and seek medical help',
          'Inspect your home for damage and gas leaks; evacuate if unsafe',
          'Be prepared for aftershocks',
          'Follow instructions from local authorities and emergency services',
        ],
      },
      'wildfire': {
        'title': 'Wildfire Safety',
        'icon': Icons.fire_extinguisher,
        'before': [
          'Create defensible space around your home',
          'Prepare an evacuation kit and plan evacuation routes',
          'Keep important documents in a safe, portable place'
        ],
        'during': [
          'Follow evacuation orders immediately',
          'Keep windows and doors closed to prevent smoke entry',
          'Use a cloth to cover nose and mouth if smoky'
        ],
        'after': [
          'Return home only when authorities say it is safe',
          'Check property for hot spots and hazards',
          'Wear protective clothing during cleanup'
        ],
      },
      'flood': {
        'title': 'Flood Safety',
        'icon': Icons.water,
        'before': [
          'Know flood risk for your area and evacuation routes',
          'Move valuables to higher ground',
          'Have a battery-powered radio and emergency kit ready'
        ],
        'during': [
          'Avoid walking or driving through flood waters',
          'Move to higher ground if flooding occurs',
          'Keep children and pets away from floodwater'
        ],
        'after': [
          'Avoid contact with floodwater; it can be contaminated',
          'Do not drink tap water until authorities confirm it is safe',
          'Document damage for insurance claims'
        ],
      },
      'cyclone': {
        'title': 'Cyclone / Hurricane Safety',
        'icon': Icons.wind_power,
        'before': [
          'Secure outdoor items and reinforce doors/windows',
          'Fill fuel and emergency supplies',
          'Follow evacuation orders for coastal areas'
        ],
        'during': [
          'Stay indoors away from windows',
          'Go to the safest room or interior space',
          'Monitor weather updates'
        ],
        'after': [
          'Avoid downed power lines and floodwater',
          'Report damage and request assistance if needed'
        ],
      },
      'pandemic': {
        'title': 'Pandemic / Public Health',
        'icon': Icons.coronavirus,
        'before': [
          'Keep hygiene supplies and masks available',
          'Stay informed on public health guidance'
        ],
        'during': [
          'Follow public health guidance and isolation rules',
          'Keep distance from others and wear masks as advised'
        ],
        'after': [
          'Continue to follow health guidance',
          'Seek medical care if symptoms persist'
        ],
      },
    };
  }

  Future<void> _initializeFirebaseAndLoadData() async {
    _db = FirebaseFirestore.instance;
    _auth = FirebaseAuth.instance;

    await _authenticateUser();
    await _loadChecklistData();
    await _loadLocalChecklist();
  }

  // SharedPreferences keys
  String get _prefsKey => 'safety_checklist_$_userId';

  Future<void> _loadLocalChecklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_prefsKey);
      if (saved != null) {
        setState(() {
          for (var item in _kitItems) {
            _kitChecked[item] = saved.contains(item);
          }
        });
      }
    } catch (e) {
      print('Error loading local checklist: $e');
    }
  }

  Future<void> _saveLocalChecklist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final completed = _kitChecked.entries.where((e) => e.value).map((e) => e.key).toList();
      await prefs.setStringList(_prefsKey, completed);
    } catch (e) {
      print('Error saving local checklist: $e');
    }
  }

  Future<void> _authenticateUser() async {
    try {
      if (__initial_auth_token.isNotEmpty) {
        final UserCredential userCredential =
            await _auth.signInWithCustomToken(__initial_auth_token);
        _userId = userCredential.user!.uid;
      } else {
        final UserCredential userCredential =
            await _auth.signInAnonymously();
        _userId = userCredential.user!.uid;
      }
    } catch (e) {
      print("Firebase Auth Error: $e");
      _userId = 'anonymous-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  DocumentReference get _checklistDocRef {
    final String appId = __app_id.isNotEmpty ? __app_id : 'default-app-id';
    return _db
        .collection('artifacts')
        .doc(appId)
        .collection('users')
        .doc(_userId)
        .collection('safety_data')
        .doc('emergency_kit');
  }

  Future<void> _loadChecklistData() async {
    try {
      final doc = await _checklistDocRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data != null) {
          setState(() {
            for (var item in _kitItems) {
              _kitChecked[item] = data[item] as bool? ?? false;
            }
          });
        }
      }
    } catch (e) {
      print("Error loading checklist: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateChecklistStatus(String item, bool isChecked) async {
    setState(() {
      _kitChecked[item] = isChecked;
    });
    // debug
    print('Checklist updated: $item -> $isChecked');
    // persist locally
    await _saveLocalChecklist();

    try {
      await _checklistDocRef.set({
        item: isChecked,
      }, SetOptions(merge: true));
    } catch (e) {
      print("Error updating checklist (keeping local state): $e");
      // Intentionally silent on sync failure; local state is authoritative.
      // Do not revert the local state; keep saved locally for later sync.
    }
  }

  int get _completedCount {
    return _kitChecked.values.where((v) => v).length;
  }

  double get _completionPercentage {
    if (_kitItems.isEmpty) return 0.0;
    return _completedCount / _kitItems.length;
  }

  String _getCompletionMessage() {
    final percentage = _completionPercentage;
    if (percentage == 1.0) {
      return 'Great! Your essential kit is complete and ready.';
    } else if (percentage > 0.75) {
      return 'Almost there! You only need a few more essentials.';
    } else if (percentage > 0.40) {
      return 'Good start! Focus on the remaining critical items.';
    } else {
      return 'You still need several essentials. Prioritize your kit!';
    }
  }

  void _showCompleteGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, controller) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              controller: controller,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      height: 5,
                      width: 50,
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  Text(
                    'Comprehensive Emergency Kit Guide',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'A comprehensive kit should sustain you and your family for at least 72 hours, preferably longer.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const Divider(height: 30),
                  _buildExtendedKitSection(Icons.medical_services, 'Health & Hygiene', [
                    'Prescription medications (7-day supply)',
                    'Diapers, wipes, and formula (if needed)',
                    'Pet food and extra water for pets',
                    'Dust masks to help filter contaminated air',
                    'Moist towelettes, garbage bags, and plastic ties for personal sanitation',
                  ]),
                  _buildExtendedKitSection(Icons.security, 'Documents & Money', [
                    'Copies of important family documents (insurance policies, identification)',
                    'Cash in small denominations',
                    'Sleeping bag or warm blanket for each person',
                    'Change of clothing for everyone',
                    'N95 masks for heavy contamination',
                  ]),
                  _buildExtendedKitSection(Icons.build, 'Tools & Shelter', [
                    'Wrench or pliers to turn off utilities',
                    'Duct tape and plastic sheeting for shelter-in-place',
                    'Fire extinguisher',
                    'Matches in a waterproof container',
                  ]),
                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close Guide'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExtendedKitSection(IconData icon, String title, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.grey.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(left: 4.0, bottom: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 4.0),
                      child: Icon(Icons.circle, size: 6, color: Colors.black54),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(fontSize: 14.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildIconTextRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.black87))),
        ],
      ),
    );
  }

  // Section header with bold text
  Widget _buildSectionHeader(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Safety Measures', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const Text('Emergency preparedness and response guidelines', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.book_outlined),
                        const SizedBox(width: 8),
                        const Text('Quick Reference', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.sos, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildQuickAction(Icons.phone_in_talk, 'Call 100'),
                        _buildQuickAction(Icons.radio, 'Listen to Radio'),
                        _buildQuickAction(Icons.directions_walk, 'Follow Evacuation'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text('Emergency Kit Checklist', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 15),
                    LinearProgressIndicator(
                      value: _completionPercentage,
                      color: _completionPercentage == 1.0 ? Colors.green : Theme.of(context).primaryColor,
                      backgroundColor: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 10,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_completedCount/${_kitItems.length} items checked. ${_getCompletionMessage()}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _completionPercentage == 1.0 ? Colors.green.shade700 : Colors.black54,
                      ),
                    ),
                    const Divider(height: 30),
                    ..._kitItems.map(_buildChecklistItem),
                    const SizedBox(height: 10),
                    // Top row: Large 'Mark all done' and smaller 'Reset' button
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            onPressed: () => _markAll(true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 1,
                            ),
                            child: const Text('Mark all done', style: TextStyle(fontSize: 16, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: ElevatedButton(
                            onPressed: () => _markAll(false),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 1,
                            ),
                            child: const Text('Reset', style: TextStyle(color: Colors.white)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // 'Complete Emergency Kit Guide' below the action buttons
                    Center(
                      child: OutlinedButton(
                        onPressed: () => _showCompleteGuide(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Complete Emergency Kit Guide'),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Disaster Response Guides', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ..._disasterGuides.entries.map((entry) => _buildGuideTile(entry.key)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label) {
    return Column(
      children: [
        CircleAvatar(
          radius: 25,
          backgroundColor: Colors.grey.shade100,
          child: Icon(icon, color: Colors.black),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildChecklistItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: CheckboxListTile(
        value: _kitChecked[text] ?? false,
        onChanged: (bool? v) => _updateChecklistStatus(text, v ?? false),
        title: Text(text),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 0.0),
        visualDensity: const VisualDensity(horizontal: 0, vertical: -0.5),
      ),
    );
  }

  void _markAll(bool checked) async {
    setState(() {
      for (var item in _kitItems) _kitChecked[item] = checked;
    });
    await _saveLocalChecklist();
    try {
      // also persist to Firestore
      final Map<String, bool> payload = {for (var k in _kitItems) k: checked};
      await _checklistDocRef.set(payload, SetOptions(merge: true));
    } catch (e) {
      print('Error marking all: $e');
    }
  }

  Widget _buildGuideTile(String disasterKey) {
    final data = _disasterGuides[disasterKey]!;
    final title = data['title'] as String;
    final IconData icon = data['icon'] as IconData;
    final List<String> before = List<String>.from(data['before'] as List);
    final List<String> during = List<String>.from(data['during'] as List);
    final List<String> after = List<String>.from(data['after'] as List);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: ExpansionTile(
        leading: Icon(icon, color: Theme.of(context).primaryColor),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader(Icons.history, 'Before / Preparedness'),
                const SizedBox(height: 6),
                ...before.map((b) => _buildIconTextRow(Icons.check_circle_outline, b)),
                const SizedBox(height: 10),
                _buildSectionHeader(Icons.crisis_alert, 'During Event'),
                const SizedBox(height: 6),
                ...during.map((d) => _buildIconTextRow(Icons.warning_amber, d)),
                const SizedBox(height: 10),
                _buildSectionHeader(Icons.construction, 'After Event'),
                const SizedBox(height: 6),
                ...after.map((a) => _buildIconTextRow(Icons.handshake_outlined, a)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
