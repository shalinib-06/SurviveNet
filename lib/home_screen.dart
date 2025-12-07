import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import for User Info and Logout
import 'screens/map_screen.dart';
import 'screens/safety_screen.dart';
import 'screens/volunteers_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/weather_screen.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Start on the Weather screen (Index 1) as it is the new main tab
  int _selectedIndex = 2; 

  // List of screens corresponding to the navigation bar items
  final List<Widget> _widgetOptions = <Widget>[
    const SosScreen(),         // Index 0: SOS Screen (Placeholder, actual SOS is full screen)
    const WeatherScreen(), // Index 1: Weather Screen
    const MapScreen(),         // Index 2: Map Screen (Disaster Alerts)
    const SafetyScreen(),      // Index 3: Safety Screen (Precautions)
    const VolunteersScreen(),  // Index 4: Volunteers Screen (Offline Assistance)
  ];

  void _onItemTapped(int index) {
    if (index == 0) {
      // Navigate to the full-screen SOS view
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SosScreen()),
      );
    } else {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  // Handles Firebase Logout
  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      // AuthStreamWrapper in main.dart will automatically navigate to LoginScreen
    } catch (e) {
      print('Logout Error: $e');
    }
    // Navigator.pop(context); // Do not pop, AuthStreamWrapper handles it
  }

  PreferredSizeWidget _buildAppBar() {
     // SOS screen uses its own AppBar
    
    // Determine the title based on the selected Index
    String title = '';
    if (_selectedIndex == 0) title ='SOS screen';
    if (_selectedIndex == 1) title = 'Local Weather'; 
    if (_selectedIndex == 2) title = 'Disaster Map';
    if (_selectedIndex == 3) title = 'Safety Measures';
    if (_selectedIndex == 4) title = 'Nearby Volunteers';

    return AppBar(
      leading: Builder(
        builder: (context) => IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Scaffold.of(context).openDrawer(); // Open the custom drawer
          },
        ),
      ),
      centerTitle: true,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lens_sharp, color: Theme.of(context).primaryColor, size: 24),
          const SizedBox(width: 4),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  // --- Widget for the Menu/Drawer ---
  Widget _buildDrawer() {
    final user = FirebaseAuth.instance.currentUser;
    // Use displayName if available, otherwise fallback to email or 'Guest'
    final userName = user?.displayName ?? user?.email ?? 'Guest User';
    
    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            height: 150, 
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade300)), // Use a lighter border for light theme
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  userName,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'User ID: ${user?.uid.substring(0, 8)}...',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Weather'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 1); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('Disaster Map'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 2); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.security_outlined),
            title: const Text('Safety Measures'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 3); 
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: const Text('Volunteers'),
            onTap: () {
              Navigator.pop(context);
              setState(() => _selectedIndex = 4); 
            },
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Get the display name, default to 'User' if null
    final userName = user?.displayName ?? 'User';
    
    // The main content area of the Home Screen
    final mainContent = Padding(
      padding: const EdgeInsets.only(top: 16.0, left: 16.0, right: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 📢 Welcome Message Section
          Text(
            'Welcome, $userName!',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Colors.black, // Dark text on light background
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Stay alert and know your surroundings.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const Divider(height: 20, color: Colors.grey),
          
          // Current selected feature screen
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _widgetOptions,
            ),
          ),
        ],
      ),
    );


    return Scaffold(
      // Only show a basic AppBar without the welcome text for the actual feature screens
      appBar: _selectedIndex == 0 ? null : _buildAppBar(), 
      drawer: _buildDrawer(),
      body: _selectedIndex == 0 
          ? const SosScreen() // SOS is fullscreen, no welcome banner
          : mainContent, // Show welcome banner and feature screen below it
      
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          // Index 0: SOS Button (Stylized)
          BottomNavigationBarItem(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.phone, color: Colors.white, size: 28),
            ),
            label: 'SOS',
          ),
          // Index 1: Weather Tab
          const BottomNavigationBarItem(
            icon: Icon(Icons.wb_sunny_outlined),
            label: 'Weather',
          ),
          // Index 2: Map
          const BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
          // Index 3: Safety
          const BottomNavigationBarItem(
            icon: Icon(Icons.security_outlined),
            label: 'Safety',
          ),
          // Index 4: Volunteers
          const BottomNavigationBarItem(
            icon: Icon(Icons.group_outlined),
            label: 'Volunteers',
          ),
        ],
        currentIndex: _selectedIndex == 0 ? 1 : _selectedIndex, // Prevent SOS button from being selected
        selectedItemColor: Theme.of(context).primaryColor, // Use theme color for selected
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).cardColor, // Use card color (white) for nav bar
        onTap: _onItemTapped,
      ),
    );
  }
}
