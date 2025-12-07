import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart'; 

import 'home_screen.dart';
import 'screens/login_screen.dart';
import 'utils/firestore_utils.dart';

void main() async {
  
  WidgetsFlutterBinding.ensureInitialized();
  
 
  try {
    await Firebase.initializeApp(
      
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully.');
    
    
    try {
      await FirestoreUtils.addSampleShelters();
      print('Sample shelter data added successfully.');
    } catch (e) {
      print('Error adding sample shelter data: $e');
    }
  } catch (e) {
    print('*** FIREBASE ERROR: Failed to initialize. Check your Firebase setup and google-services.json. Error: $e');
  }
  
  runApp(const SurviveNetApp());
}

class SurviveNetApp extends StatelessWidget {
  const SurviveNetApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primaryRed = Color(0xFFE53935);
    
    return MaterialApp(
      title: 'SurviveNet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Set Primary Color
        primarySwatch: Colors.red,
        primaryColor: primaryRed, 
        
        // Custom Light Background Color
        scaffoldBackgroundColor: Colors.grey[50],

        // AppBar Theme (Light background, black text)
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[50],
          foregroundColor: Colors.black,
          elevation: 0,
          toolbarHeight: 60,
          iconTheme: const IconThemeData(color: Colors.black),
        ),
        
        // Custom TextButton Theme (Black background, white text)
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            backgroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),

        // Add the Input Decoration Theme from the Light Theme for inputs on Login/Signup
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white, // White fill for input fields on grey background
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryRed, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.black54),
          hintStyle: TextStyle(color: Colors.grey.shade400),
          prefixIconColor: Colors.black54,
          suffixIconColor: Colors.black54,
        ),
        
        // Add the standard ElevatedButton theme (Red CTA)
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryRed,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            elevation: 2,
          ),
        ),
        
        // Add Bottom Navigation Bar Theme
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          backgroundColor: Colors.white,
          selectedItemColor: primaryRed,
          unselectedItemColor: Colors.black54,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
      ),
      // --- Routing Logic ---
      // Use the AuthStreamWrapper to handle navigation based on login status.
      home: const AuthStreamWrapper(), 
    );
  }
}


// Wrapper to handle routing based on authentication state
class AuthStreamWrapper extends StatelessWidget {
  const AuthStreamWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // This line tries to access Firebase Auth, which is why it failed before init.
    // The fix above ensures Firebase.initializeApp() runs first.
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        // Check if the user is logged in
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        
        // User is not logged in, show the Login screen
        return const LoginScreen();
      },
    );
  }
}
