
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

String formatTimeAgo(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inSeconds < 60) {
    return 'just now';
  } else if (difference.inMinutes < 60) {
    return '${difference.inMinutes} min ago';
  } else if (difference.inHours < 24) {
    return '${difference.inHours} hours ago';
  } else if (difference.inDays < 7) {
    return '${difference.inDays} days ago';
  } else {
    return 'on ${time.month}/${time.day}';
  }
}

// Global variables provided by the Canvas environment for Firebase setup.
const String __app_id = 'survivenet';


// List of all available skills for registration and filtering
const List<String> availableSkills = ['Medical', 'Shelter', 'Food', 'Logistics', 'Search & Rescue', 'Tech Support', 'Child Care', 'Pet Rescue','Miscellaneous'];


// --- 1. Data Model for Volunteer ---
class Volunteer {
  final String id;
  final String name;
  final String phone;
  final String skills; // e.g., "Shelter, Food Distribution"
  final String description; 
  final String userId;
  final double rating;
  final String city; // New field for city/location
  final DateTime registrationTime; // New field for real timestamp
  final bool isAvailable; // Crucial for visibility toggle
  final bool isVerified; // New: Verification status

  Volunteer({
    required this.id,
    required this.name,
    required this.phone,
    required this.skills,
    required this.userId,
    required this.city, 
    required this.registrationTime, 
    this.description = 'Community assistant and organizer.', 
    this.rating = 0.0, 
    this.isAvailable = true, // Default to true
    this.isVerified = false, // Default to false
  });

  factory Volunteer.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    
    // Convert Firestore Timestamp to Dart DateTime
    Timestamp? timestamp = data['timestamp'] as Timestamp?;
    DateTime time = timestamp?.toDate() ?? DateTime.now();
    
    // Calculate average rating
    final ratingsMap = data['ratings'] is Map ? Map<String, int>.from(data['ratings']) : <String, int>{};
    final totalRating = ratingsMap.values.fold(0, (sum, element) => sum + element);
    final ratingCount = ratingsMap.length;
    final averageRating = ratingCount > 0 ? (totalRating / ratingCount) : 0.0;

    return Volunteer(
      id: doc.id,
      name: data['name'] ?? 'Unknown Volunteer',
      phone: data['phone'] ?? 'N/A',
      skills: data['skills'] ?? 'General Assistance',
      description: data['description'] ?? 'Community assistant and organizer.',
      userId: data['userId'] ?? '',
      city: data['city'] ?? 'Unknown Location', 
      registrationTime: time, 
      rating: averageRating,
      isAvailable: data['isAvailable'] ?? true, // Read isAvailable state
      isVerified: data['isVerified'] ?? false, // Read isVerified state
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'skills': skills,
      'description': description,
      'userId': userId,
      'city': city, 
      'timestamp': FieldValue.serverTimestamp(), 
      'ratings': {}, // Initialize with empty map for user ratings (userId -> score)
      'isAvailable': isAvailable, // Save isAvailable state
      'isVerified': isVerified, // Save isVerified state
    };
  }
}

// --- Team data model for Emergency Teams ---
class Team {
  final String id;
  final String name;
  final int membersCount;
  final String city;
  final String phone;
  final String skills; // comma separated
  final String status; // e.g., active, standby
  final DateTime createdAt;

  Team({
    required this.id,
    required this.name,
    required this.membersCount,
    required this.city,
    required this.phone,
    required this.skills,
    required this.status,
    required this.createdAt,
  });

  factory Team.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final Timestamp? ts = data['createdAt'] as Timestamp?;
    return Team(
      id: doc.id,
      name: data['name'] ?? 'Unnamed Team',
      membersCount: (data['membersCount'] is int) ? data['membersCount'] as int : int.tryParse('${data['membersCount'] ?? 0}') ?? 0,
      city: data['city'] ?? 'Unknown',
      phone: data['phone'] ?? '',
      skills: data['skills'] ?? '',
      status: data['status'] ?? 'standby',
      createdAt: ts?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'membersCount': membersCount,
      'city': city,
      'phone': phone,
      'skills': skills,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

class VolunteersScreen extends StatefulWidget {
  const VolunteersScreen({super.key});

  @override
  State<VolunteersScreen> createState() => _VolunteersScreenState();
}

class _VolunteersScreenState extends State<VolunteersScreen> {
  // --- 2. Firebase Setup & State ---
  late final FirebaseFirestore db;
  late final FirebaseAuth auth;
  String? userId;
  bool isAuthReady = false;
  
  List<Volunteer> allVolunteers = []; 
  Volunteer? currentUserVolunteerProfile; 
  Set<String> adminUserIds = {}; // NEW: Set to store authorized admin IDs
  
  // State for Search and Filter
  String _searchQuery = '';
  String _selectedSkill = 'All Skills';
  final List<String> filterSkills = ['All Skills', ...availableSkills];
  
  // State for Registration/Editing Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _descriptionController = TextEditingController(); 
  final _cityController = TextEditingController();
  
  // Controller used for search
  final _searchController = TextEditingController(); 
  
  Set<String> _selectedRegistrationSkills = {}; 
  // Teams state
  List<Team> emergencyTeams = [];

  String get _teamCollectionPath => 'artifacts/$__app_id/public/data/roles/emergency_teams/emergency_teams';


  @override
  void initState() {
    super.initState();
    _initializeFirebase();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _cityController.dispose(); 
    _searchController.dispose();
    super.dispose();
  }
  
  // --- Search Logic Handler ---
  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _initializeFirebase() async {
    try {
      final app = Firebase.app();
      db = FirebaseFirestore.instanceFor(app: app);
      auth = FirebaseAuth.instanceFor(app: app);

      // Rely on the existing authenticated user. This screen assumes the
      // user has already signed in using the app's primary auth flow
      // (email/password or federated). Attempting to sign in anonymously or
      // with a custom token here caused permission errors when an authenticated
      // user reached this screen.
      final current = auth.currentUser;
      if (current != null) {
        setState(() {
          userId = current.uid;
          isAuthReady = true;
        });
        _setupVolunteerListener();
        _setupAdminListener();
        _setupTeamListener();
      } else {
        // If there is no authenticated user, do not sign in automatically.
        // Instead, show guidance so the caller (login flow) can handle auth.
        debugPrint('No authenticated user present when opening VolunteersScreen.');
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Authentication required'),
              content: const Text('You must be signed in to access volunteer features. Please sign in with your account.'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
              ],
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Firebase initialization error: $e");
      // Show an error dialog if initialization fails
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error initializing Firebase'),
            content: Text('Failed to initialize Firebase: $e'),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  void _setupTeamListener() {
    db.collection(_teamCollectionPath).snapshots().listen((snapshot) {
      setState(() {
        emergencyTeams = snapshot.docs.map(Team.fromFirestore).toList();
      });
    }, onError: (e) {
      debugPrint('Error listening to teams: $e');
    });
  }

  Future<void> _addTeam(Team team) async {
    if (userId == null || !adminUserIds.contains(userId)) {
      _showSnackbar('Only admins can add teams.', isError: true);
      return;
    }

    try {
      await db.collection(_teamCollectionPath).add(team.toFirestore());
      _showSnackbar('Team added successfully.');
    } catch (e) {
      debugPrint('Error adding team: $e');
      _showSnackbar('Failed to add team: $e', isError: true);
    }
  }

  Future<void> _deleteTeam(Team team) async {
    if (userId == null || !adminUserIds.contains(userId)) {
      _showSnackbar('Only admins can delete teams.', isError: true);
      return;
    }

    try {
      await db.collection(_teamCollectionPath).doc(team.id).delete();
      _showSnackbar('Team deleted.');
    } catch (e) {
      debugPrint('Error deleting team: $e');
      _showSnackbar('Failed to delete team: $e', isError: true);
    }
  }
  
  String get _volunteerCollectionPath => 
    'artifacts/$__app_id/public/data/roles/volunteers/volunteers';
    
  String get _adminRoleCollectionPath =>
    'artifacts/$__app_id/public/data/roles/admin_users/admin_users'; // NEW Collection Path

  // NEW: Setup listener for Admin User IDs
  void _setupAdminListener() {
    db.collection(_adminRoleCollectionPath)
      .snapshots()
      .listen((snapshot) {
        setState(() {
          // Store all document IDs (which are the User IDs) in the set
          adminUserIds = snapshot.docs.map((doc) => doc.id).toSet();
        });
        debugPrint('Admin IDs loaded: ${adminUserIds.length}');
      }, onError: (error) {
        debugPrint("Error listening to admin roles: $error");
      });
  }


  void _setupVolunteerListener() {
    if (userId == null) return;
    
    db.collection(_volunteerCollectionPath)
      .snapshots()
      .listen((snapshot) {
        setState(() {
          allVolunteers = snapshot.docs
              .map(Volunteer.fromFirestore)
              .where((v) => v.name != 'Unknown Volunteer' && v.phone != 'N/A')
              .toList();
              
          // Update the current user's profile state
          final userProfile = allVolunteers.cast<Volunteer?>().firstWhere(
            (v) => v?.userId == userId, 
            orElse: () => null
          );
          currentUserVolunteerProfile = userProfile;
        });
      }, onError: (error) {
        debugPrint("Error listening to volunteers: $error");
      });
  }

  // --- Filtering Logic (Only show available volunteers) ---
  List<Volunteer> get _filteredVolunteers {
    // 0. Filter by Availability (NEW: only show if isAvailable is true)
    List<Volunteer> availableVolunteers = allVolunteers
        .where((volunteer) => volunteer.isAvailable)
        .toList();

    // 1. Filter by Skill
    List<Volunteer> skillFiltered = availableVolunteers.where((volunteer) {
      if (_selectedSkill == 'All Skills') return true;
      return volunteer.skills.toLowerCase().contains(_selectedSkill.toLowerCase());
    }).toList();

    // 2. Filter by Search Query
    if (_searchQuery.isEmpty) {
      return skillFiltered;
    }

    return skillFiltered.where((volunteer) {
      final query = _searchQuery;
      return volunteer.name.toLowerCase().contains(query) || 
             volunteer.skills.toLowerCase().contains(query) ||
             volunteer.description.toLowerCase().contains(query) ||
             volunteer.city.toLowerCase().contains(query);
    }).toList();
  }


  // --- Firestore: Register Volunteer ---
  Future<void> _registerVolunteer(String name, String phone, String city, String description, String skills) async {
    if (userId == null) {
      _showSnackbar('Please wait, authentication is in progress.', isError: true);
      return;
    }
    
    if (city.trim().isEmpty) {
       _showSnackbar('Location/City is required for registration.', isError: true);
       return;
    }

    try {
      final existingDoc = await db.collection(_volunteerCollectionPath)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();
          
      if (existingDoc.docs.isNotEmpty) {
        _showSnackbar('You are already registered as a volunteer!', isError: true);
        return;
      }
      
      final newVolunteer = Volunteer(
        id: '', 
        name: name,
        phone: phone,
        description: description,
        skills: skills.isEmpty ? 'General Assistance' : skills,
        userId: userId!,
        city: city,
        registrationTime: DateTime.now(),
        isAvailable: true,
        isVerified: false, 
      );

      await db.collection(_volunteerCollectionPath).add(newVolunteer.toFirestore());
      _showSnackbar('Successfully registered as a volunteer! Ready to help.');
    } catch (e) {
      debugPrint("Error registering volunteer: $e");
      _showSnackbar('Failed to register: $e', isError: true);
    }
  }
  
  // --- Firestore: Update Volunteer Profile ---
  Future<void> _updateVolunteerProfile(Volunteer volunteer, String newName, String newPhone, String newDescription, String newSkills, String newCity, {bool showSnackbar = true}) async {
    if (userId == null || volunteer.userId != userId) return;
    
    if (newCity.trim().isEmpty) {
      _showSnackbar('Location/City cannot be empty. Please enter your location-city.', isError: true);
      return;
    }

    try {
      final volunteerRef = db.collection(_volunteerCollectionPath).doc(volunteer.id);
      
      await volunteerRef.update({
        'name': newName,
        'phone': newPhone,
        'description': newDescription,
        'skills': newSkills.isEmpty ? 'General Assistance' : newSkills,
        'city': newCity,
      });

      if (showSnackbar) {
        _showSnackbar('Your profile details have been successfully updated.');
      }
    } catch (e) {
      debugPrint("Error updating profile: $e");
      _showSnackbar('Failed to update profile: $e', isError: true);
    }
  }

  
  // --- Firestore: Toggle Availability ---
  Future<void> _toggleAvailability(Volunteer volunteer, bool newValue) async {
    if (userId == null || volunteer.userId != userId) return;

    try {
      final volunteerRef = db.collection(_volunteerCollectionPath).doc(volunteer.id);
      await volunteerRef.update({'isAvailable': newValue});

      final status = newValue ? 'visible' : 'hidden';
      _showSnackbar('Your volunteer profile is now $status.');
    } catch (e) {
      debugPrint("Error toggling availability: $e");
      _showSnackbar('Failed to update availability: $e', isError: true);
    }
  }
  
  // --- Firestore: Toggle Verification (Admin Action Simulation) ---
  // NOW protected by checking against the adminUserIds set (client-side)
  // And must be protected by Firebase Security Rules (server-side)
  Future<void> _toggleVerification(Volunteer volunteer, bool newValue) async {
    // Client-side check: must be logged in AND an authorized admin
    if (userId == null || !adminUserIds.contains(userId)) {
      _showSnackbar('Authorization failed. Only verified organization staff can change verification status.', isError: true);
      return;
    }

    try {
      final volunteerRef = db.collection(_volunteerCollectionPath).doc(volunteer.id);
      await volunteerRef.update({'isVerified': newValue});

      final status = newValue ? 'Verified' : 'Unverified';
      _showSnackbar('${volunteer.name} profile is now $status.', isError: !newValue);
    } catch (e) {
      debugPrint("Error toggling verification: $e");
      _showSnackbar('Failed to update verification status: $e. Check Firebase Security Rules.', isError: true);
    }
  }
  
  // --- Firestore: Delete Profile ---
  Future<void> _deleteProfile(Volunteer volunteer) async {
    if (userId == null || volunteer.userId != userId) return;

    try {
      final volunteerRef = db.collection(_volunteerCollectionPath).doc(volunteer.id);
      await volunteerRef.delete();
      
      currentUserVolunteerProfile = null; // Clear local state
      _showSnackbar('Your volunteer profile has been successfully deleted.');
      Navigator.of(context).pop(); // Close confirmation dialog
    } catch (e) {
      debugPrint("Error deleting profile: $e");
      _showSnackbar('Failed to delete profile: $e', isError: true);
    }
  }
  
  // --- Firestore: Submit Rating ---
  Future<void> _submitRating(String volunteerDocId, int score) async {
    if (userId == null) {
      _showSnackbar('Authentication required to submit a rating.', isError: true);
      return;
    }

    try {
      final volunteerRef = db.collection(_volunteerCollectionPath).doc(volunteerDocId);
      
      // Use FieldValue.update to set the rating under the current user's ID
      await volunteerRef.update({
        'ratings.$userId': score,
      });

      _showSnackbar('Rating submitted successfully!');
    } catch (e) {
      debugPrint("Error submitting rating: $e");
      _showSnackbar('Failed to submit rating: $e', isError: true);
    }
  }


  // --- Utility Functions: Call/Message and Snackbar ---
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      // Use external app mode to force open phone or messaging app
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackbar('Could not launch $url', isError: true);
    }
  }

  void _callVolunteer(String phoneNumber) {
    _launchUrl('tel:$phoneNumber');
  }

  void _messageVolunteer(String phoneNumber) {
    _launchUrl('sms:$phoneNumber');
  }
  
  void _showSnackbar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.deepOrange : Colors.lightGreen.shade700,
        ),
      );
    }
  }
  
  // --- Rating Dialog ---
  void _showRatingDialog(Volunteer volunteer) {
    // Default to 0 so no stars are filled by default
    int tempRating = 0;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text('Rate ${volunteer.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How would you rate this volunteer\'s assistance?'),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(
                          index < tempRating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 36,
                        ),
                        onPressed: () {
                          setState(() {
                            tempRating = index + 1;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: <Widget>[
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.black12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 237, 97, 97),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Submit'),
                  onPressed: tempRating > 0 ? () {
                    Navigator.of(context).pop();
                    _submitRating(volunteer.id, tempRating);
                  } : null,
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Confirmation Dialog for Deletion ---
  void _showDeleteConfirmationDialog(Volunteer volunteer) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Confirm Deletion', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          content: const Text('Are you sure you want to completely remove your volunteer profile? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Delete Profile', style: TextStyle(color: Colors.white)),
              onPressed: () => _deleteProfile(volunteer),
            ),
          ],
        );
      },
    );
  }
  
  // --- Edit Profile Dialog ---
  void _showEditProfileDialog(Volunteer volunteer) {
    // Initialize controllers with current profile data
    _nameController.text = volunteer.name;
    _phoneController.text = volunteer.phone;
    _descriptionController.text = volunteer.description;
    _cityController.text = volunteer.city;
    
    // Initialize selected skills from the profile string
    _selectedRegistrationSkills = volunteer.skills.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Edit Your Profile', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    // Name
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Phone
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number (Required for Contact)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // City (Manual Input Only)
                    TextField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: 'City / Location (Required)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Description
                    TextField(
                      controller: _descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Short Description',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.info_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Skills
                    _buildSkillMultiSelectDropdown(setState),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Save', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    if (_nameController.text.trim().isNotEmpty && _phoneController.text.trim().isNotEmpty && _cityController.text.trim().isNotEmpty) {
                      _updateVolunteerProfile(
                        volunteer,
                        _nameController.text.trim(),
                        _phoneController.text.trim(),
                        _descriptionController.text.trim().isEmpty ? 'Community assistant and organizer.' : _descriptionController.text.trim(),
                        _selectedRegistrationSkills.join(', '),
                        _cityController.text.trim(),
                      );
                      Navigator.of(context).pop();
                    } else {
                      _showSnackbar('Name, Phone, and Location are required.', isError: true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- Skill Multi-Select Dropdown Widget ---
  Widget _buildSkillMultiSelectDropdown(StateSetter setState) {
    return InkWell(
      onTap: () async {
        final List<String>? result = await showDialog<List<String>>(
          context: context,
          builder: (context) => _SkillSelectionDialog(
            allSkills: availableSkills,
            initialSelectedSkills: _selectedRegistrationSkills.toList(),
          ),
        );
        if (result != null) {
          setState(() {
            _selectedRegistrationSkills = result.toSet();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.volunteer_activism_outlined, color: Colors.black54),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _selectedRegistrationSkills.isEmpty
                    ? 'Select Skills (e.g., Medical)'
                    : _selectedRegistrationSkills.join(', '),
                style: TextStyle(
                  color: _selectedRegistrationSkills.isEmpty ? Colors.black54 : Colors.black,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.black54),
          ],
        ),
      ),
    );
  }

  // --- Registration Form Dialog ---
  void _showRegistrationDialog(BuildContext context) {
    final TextEditingController regNameController = TextEditingController();
    final TextEditingController regPhoneController = TextEditingController();
    final TextEditingController regCityController = TextEditingController();
    final TextEditingController regDescriptionController = TextEditingController();
    
    _selectedRegistrationSkills = {}; 
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Become a Volunteer', style: TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    // City/Location Input (New Required Field)
                    TextField(
                      controller: regCityController,
                      decoration: InputDecoration(
                        labelText: 'City / Location (Required)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.location_city_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Name
                    TextField(
                      controller: regNameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Phone
                    TextField(
                      controller: regPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number (Required for Contact)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.phone_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Description
                    TextField(
                      controller: regDescriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Short Description (e.g., "Nurse available 24/7")',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.info_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSkillMultiSelectDropdown(setState),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel', style: TextStyle(color: Color.fromARGB(255, 237, 233, 233))),
                  onPressed: () {
                    Navigator.of(context).pop();
                    regNameController.dispose();
                    regPhoneController.dispose();
                    regCityController.dispose();
                    regDescriptionController.dispose();
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Register', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    if (regNameController.text.trim().isNotEmpty && 
                        regPhoneController.text.trim().isNotEmpty && 
                        regCityController.text.trim().isNotEmpty) {
                      
                      _registerVolunteer(
                        regNameController.text.trim(),
                        regPhoneController.text.trim(),
                        regCityController.text.trim(),
                        regDescriptionController.text.trim().isEmpty ? 'Community assistant and organizer.' : regDescriptionController.text.trim(),
                        _selectedRegistrationSkills.join(', '),
                      );
                      Navigator.of(context).pop();
                      regNameController.dispose();
                      regPhoneController.dispose();
                      regCityController.dispose();
                      regDescriptionController.dispose();
                    } else {
                      _showSnackbar('Name, Phone Number, and Location are required.', isError: true);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
        // Clean up controllers if dialog dismissed via outside tap
        regNameController.dispose();
        regPhoneController.dispose();
        regCityController.dispose();
        regDescriptionController.dispose();
    });
  }
  
  // --- Admin Action Button Helper (Simulates Verification Control) ---
  Widget _buildAdminActionButton(Volunteer volunteer) {
    // NEW: Check if the current user is an admin
    if (userId == null || !adminUserIds.contains(userId)) {
      return const SizedBox.shrink(); // Hide the button if not an admin
    }
    
    final primaryColor = Theme.of(context).primaryColor;
    final isVerified = volunteer.isVerified;
    
    return Container(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: Colors.black12),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8.0),
            child: Text('Admin Controls (Visible to organization staff only)', style: TextStyle(fontSize: 10, color: Colors.deepOrange)),
          ),
          OutlinedButton.icon(
            onPressed: () => _toggleVerification(volunteer, !isVerified),
            icon: Icon(isVerified ? Icons.person_remove_outlined : Icons.verified_user_outlined, size: 20, color: isVerified ? Colors.deepOrange : primaryColor),
            label: Text(
              isVerified ? 'Remove Verification' : 'Mark as Verified',
              style: TextStyle(color: isVerified ? Colors.deepOrange : primaryColor),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: isVerified ? Colors.deepOrange.shade100 : primaryColor.withAlpha(50)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dynamic Volunteer Card Widget (UPDATED for Badges) ---
  Widget _buildVolunteerCard(Volunteer volunteer) {
    final primaryColor = Theme.of(context).primaryColor;
    final List<String> skillList = volunteer.skills.split(',').map((s) => s.trim()).toList();
    
    // Display average rating or 'New' if no ratings
    final String ratingDisplay = volunteer.rating > 0.0 
        ? volunteer.rating.toStringAsFixed(1)
        : 'New';

    // Display formatted time
    final String timeAgo = formatTimeAgo(volunteer.registrationTime);


    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Row: Avatar, Name, and Availability Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                backgroundColor: primaryColor.withAlpha(25),
                radius: 24,
                child: Text(
                  volunteer.name.isNotEmpty ? volunteer.name[0].toUpperCase() : 'V',
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and Verified Badge (word-style similar to AVAILABLE)
                    Row(
                      children: [
                        // Make name flexible so it doesn't push other items off-screen
                        Expanded(
                          child: Text(
                            volunteer.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // --- VERIFIED WORD BADGE (GREEN) ---
                        if (volunteer.isVerified) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Verified Volunteer',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'VERIFIED',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Location, Rating, Time
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: Colors.black54, size: 14),
                        const SizedBox(width: 4),
                        // City can be long; allow it to truncate nicely
                        Flexible(
                          child: Text(
                            volunteer.city,
                            style: const TextStyle(fontSize: 13, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          volunteer.rating > 0 ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        // Rating and time should also be flexible to avoid overflow
                        Flexible(
                          child: Text(
                            '$ratingDisplay • $timeAgo',
                            style: const TextStyle(fontSize: 13, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // --- AVAILABILITY + VERIFIED BADGE ---
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: volunteer.isAvailable ? Colors.blue.shade50 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Availability text (keeps previous color intent)
                    Text(
                      volunteer.isAvailable ? 'AVAILABLE' : 'HIDDEN',
                      style: TextStyle(
                        color: volunteer.isAvailable ? Colors.blue.shade700 : Colors.red.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const Divider(height: 24),

          // Description
          Text(
            volunteer.description,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 12),

          // Skills Chips
          Wrap(
            spacing: 8.0,
            runSpacing: 8.0,
            children: skillList.where((skill) => skill.isNotEmpty).map((skill) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: primaryColor.withAlpha(25),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                skill,
                style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600),
              ),
            )).toList(),
          ),
          
          const SizedBox(height: 20),
          
          // Rate Button (uses app theme color)
          ElevatedButton.icon(
            onPressed: () => _showRatingDialog(volunteer),
            icon: Icon(Icons.star_border, color: Colors.white, size: 20),
            label: Text('Rate Volunteer', style: TextStyle(color: Colors.white, fontSize: 14)),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 1,
            ),
          ),
          
          // --- ADMIN ACTION BUTTON (Toggle Verification) ---
          // This calls the method which has client-side security
          _buildAdminActionButton(volunteer), 
          
          const SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _callVolunteer(volunteer.phone),
                  icon: const Icon(Icons.call_outlined, size: 20, color: Colors.black),
                  label: const Text('Call', style: TextStyle(color: Colors.black)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _messageVolunteer(volunteer.phone),
                  icon: const Icon(Icons.message_outlined, size: 20, color: Colors.white),
                  label: const Text('Message'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  // --- Profile Management Card ---
  Widget _buildProfileManagementCard(Volunteer volunteer) {
    final statusColor = volunteer.isAvailable ? Colors.green.shade700 : Colors.deepOrange.shade700;
    final statusText = volunteer.isAvailable ? 'Available (Profile Visible)' : 'Unavailable (Profile Hidden)';
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: statusColor.withAlpha(20),
        border: Border.all(color: statusColor.withAlpha(50)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('Your Volunteer Profile', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  // Display your own verification status here
                  if (volunteer.isVerified) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Verified',
                      child: Icon(Icons.verified_user, color: Colors.green.shade700, size: 15),
                    ),
                  ],
                ],
              ),
              // Edit Profile Button
              TextButton.icon(
                onPressed: () => _showEditProfileDialog(volunteer),
                icon: const Icon(Icons.edit_outlined, size: 10),
                label: const Text('Edit Profile'),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: statusColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      volunteer.isAvailable ? 'You can be contacted for help.' : 'Your profile is hidden from others.',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Switch(
                value: volunteer.isAvailable,
                onChanged: (newValue) => _toggleAvailability(volunteer, newValue),
                activeColor: Colors.green.shade700,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Delete Button
          TextButton.icon(
            onPressed: () => _showDeleteConfirmationDialog(volunteer),
            icon: const Icon(Icons.delete_outline, size: 20, color: Colors.deepOrange),
            label: const Text('Delete my profile', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  // Helper function for the Network Stats box
  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
              color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white70),
        ),
      ],
    );
  }
/*
  // Helper for static team cards (retained from previous version)
  Widget _buildTeamCard({required String name, required String details, required List<String> skills, required String status}) {
    final statusColor = status == 'active' ? Colors.blue.shade700 : Colors.deepOrange.shade700;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16.0, top: 10),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.group_work, color: Colors.blue.shade700, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6.0,
                  runSpacing: 4.0,
                  children: skills.map((skill) => Chip(
                    label: Text(skill, style: const TextStyle(fontSize: 11, color: Colors.blue)),
                    backgroundColor: Colors.blue.shade100,
                    padding: EdgeInsets.zero,
                  )).toList(),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withAlpha(25), 
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
*/

  // --- Main Build Method ---
  @override
  Widget build(BuildContext context) {
    if (!isAuthReady) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Check if the current user is an admin for conditional UI rendering
    final bool isAdmin = adminUserIds.contains(userId);

    final verifiedCount = allVolunteers.where((v) => v.isVerified).length;
    
    // dynamic teams from Firestore
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Emergency Response Network Summary (Dynamic Counts) ---
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.group_outlined, color: Colors.white, size: 50),
                  const Text('Emergency Response Network',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(allVolunteers.length.toString(), 'Volunteers'), 
                      const SizedBox(
                        height: 40,
                        child: VerticalDivider(color: Colors.white54),
                      ),
                      _buildStatItem(verifiedCount.toString(), 'Verified'),
                      const SizedBox(
                        height: 40,
                        child: VerticalDivider(color: Colors.white54),
                      ),
                      _buildStatItem(emergencyTeams.length.toString(), 'Teams'),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 20),
            
            // --- Volunteer Management Card (NEW: ONLY for Registered Users) ---
            if (currentUserVolunteerProfile != null)
              _buildProfileManagementCard(currentUserVolunteerProfile!),
            
            const SizedBox(height: 10),


            // --- Search and Filter Bar ---
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search name, skill, location, or description',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                
                // Skill Filter Dropdown
                DropdownButtonHideUnderline(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: _selectedSkill,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w500, fontSize: 14),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSkill = newValue!;
                        });
                      },
                      items: filterSkills.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Row(
                            children: [
                              if (value != 'All Skills') const Icon(Icons.filter_list, size: 18, color: Colors.black54),
                              if (value != 'All Skills') const SizedBox(width: 5),
                              Text(value),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // --- Emergency Teams Section (Static Mock Data) ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Emergency Teams', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => _showAddTeamDialog(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Team'),
                  ),
              ],
            ),

            const SizedBox(height: 8),
            if (emergencyTeams.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Text('No emergency teams available.', style: TextStyle(color: Colors.black54)),
              )
            else
              ...emergencyTeams.map((team) => _buildTeamCardFromModel(team)),

            const SizedBox(height: 20),

            // --- Individual Volunteers Section (Dynamic Data with Filtering) ---
            const Text('Individual Volunteers',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),

            // Use the filtered list here
            if (_filteredVolunteers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Center(
                  child: Text(
                    _searchQuery.isNotEmpty || _selectedSkill != 'All Skills'
                        ? 'No active volunteers matched your criteria.' 
                        : 'No individual volunteers are currently active.', 
                    style: const TextStyle(color: Colors.black54)
                  ),
                ),
              )
            else
              ..._filteredVolunteers.map(_buildVolunteerCard),


            const SizedBox(height: 30),

            // --- Want to Help Card (Registration) ---
            // Only show if the user is NOT registered
            if (currentUserVolunteerProfile == null)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Column(
                  children: [
                    const Text('Want to help?',
                        style:
                            TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(
                      'Join our volunteer network and help your community during emergencies',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(height: 15),
                    OutlinedButton(
                      onPressed: () => _showRegistrationDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.deepOrange,
                        side: const BorderSide(color: Colors.deepOrange),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 30, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Become a Volunteer'),
                    )
                  ],
                ),
              ),
            const SizedBox(height: 30),
            // Display current user ID (MANDATORY for public data apps)
            Text(
              'Your User ID (For Admin Access): ${userId ?? 'Loading...'}',
              style: const TextStyle(fontSize: 10, color: Colors.black38),
            ),
            // NEW: Instructions for adding admin role
            if (userId != null && !isAdmin)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'We ensure all volunteers are verified by our team.',
                  style: TextStyle(fontSize: 10, color: Colors.deepOrange.shade700, fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // --- Admin: Add Team Dialog ---
  void _showAddTeamDialog(BuildContext context) {
    final _teamName = TextEditingController();
    final _teamCity = TextEditingController();
    final _teamPhone = TextEditingController();
    final _teamMembers = TextEditingController(text: '1');
    Set<String> _selectedSkills = {};
    String _status = 'standby';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text('Add Emergency Team', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: _teamName, decoration: const InputDecoration(labelText: 'Team Name')),
                  const SizedBox(height: 8),
                  TextField(controller: _teamCity, decoration: const InputDecoration(labelText: 'City / Location')),
                  const SizedBox(height: 8),
                  TextField(controller: _teamPhone, decoration: const InputDecoration(labelText: 'Contact Phone')),
                  const SizedBox(height: 8),
                  TextField(controller: _teamMembers, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Number of Members')),
                  const SizedBox(height: 8),
                  // Skills multi-select simplified as chips
                  Wrap(
                    spacing: 6,
                    children: availableSkills.map((skill) {
                      final selected = _selectedSkills.contains(skill);
                      return ChoiceChip(
                        label: Text(skill),
                        selected: selected,
                        onSelected: (s) => setState(() => selected ? _selectedSkills.remove(skill) : _selectedSkills.add(skill)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _status,
                    items: const [
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'standby', child: Text('Standby')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'standby'),
                    decoration: const InputDecoration(labelText: 'Status'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final name = _teamName.text.trim();
                  final city = _teamCity.text.trim();
                  final phone = _teamPhone.text.trim();
                  final members = int.tryParse(_teamMembers.text.trim()) ?? 1;
                  if (name.isEmpty || city.isEmpty) {
                    _showSnackbar('Team name and city are required.', isError: true);
                    return;
                  }
                  final team = Team(
                    id: '',
                    name: name,
                    membersCount: members,
                    city: city,
                    phone: phone,
                    skills: _selectedSkills.join(', '),
                    status: _status,
                    createdAt: DateTime.now(),
                  );
                  _addTeam(team);
                  Navigator.of(context).pop();
                },
                child: const Text('Add'),
              )
            ],
          );
        });
      },
    );
  }

  // Build a team card from Team model with admin delete and contact button
  Widget _buildTeamCardFromModel(Team team) {
    final statusColor = team.status == 'active' ? Colors.green.shade700 : Colors.deepOrange.shade700;
    final primaryColor = Theme.of(context).primaryColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 16.0),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: primaryColor.withAlpha(25),
                radius: 22,
                child: Text(
                  team.name.isNotEmpty ? team.name[0].toUpperCase() : 'T',
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(team.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                        if (adminUserIds.contains(userId))
                          IconButton(
                            onPressed: () => _deleteTeam(team),
                            icon: const Icon(Icons.delete_outline, color: Colors.deepOrange),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${team.membersCount} members • ${team.city}', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  team.status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (team.skills.trim().isNotEmpty) ...[
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: team.skills.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).map((skill) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(skill, style: TextStyle(fontSize: 12, color: primaryColor, fontWeight: FontWeight.w600)),
              )).toList(),
            ),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: team.phone.isNotEmpty ? () => _launchUrl('tel:${team.phone}') : null,
                  icon: const Icon(Icons.call_outlined, size: 18, color: Colors.black),
                  label: const Text('Contact Team', style: TextStyle(color: Colors.black)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.black12),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Custom skill selection dialog widget to handle multi-select logic
class _SkillSelectionDialog extends StatefulWidget {
  final List<String> allSkills;
  final List<String> initialSelectedSkills;

  const _SkillSelectionDialog({
    required this.allSkills,
    required this.initialSelectedSkills,
  });

  @override
  __SkillSelectionDialogState createState() => __SkillSelectionDialogState();
}

class __SkillSelectionDialogState extends State<_SkillSelectionDialog> {
  late Set<String> _selectedSkills;

  @override
  void initState() {
    super.initState();
    _selectedSkills = widget.initialSelectedSkills.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select Your Skills', style: TextStyle(fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.allSkills.map((skill) {
            return CheckboxListTile(
              title: Text(skill),
              value: _selectedSkills.contains(skill),
              onChanged: (bool? isChecked) {
                setState(() {
                  if (isChecked == true) {
                    _selectedSkills.add(skill);
                  } else {
                    _selectedSkills.remove(skill);
                  }
                });
              },
            );
          }).toList(),
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Done'),
          onPressed: () {
            Navigator.of(context).pop(_selectedSkills.toList());
          },
        ),
      ],
    );
  }
}
