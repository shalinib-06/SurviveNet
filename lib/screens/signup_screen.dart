import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Core Firebase Sign Up Logic ---
  Future<void> _signUpWithEmailAndPassword() async {
    setState(() {
      _isLoading = true;
    });

    final String name = _nameController.text.trim();
    final String email = _emailController.text.trim();
    final String password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showSnackBar('Please fill in all fields.', isError: true);
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 1. Create the user
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      
      // 2. Set the display name immediately after creation
      await userCredential.user!.updateDisplayName(name);

      // 3. Show the enhanced success message
      _showSnackBar('Welcome aboard! Your account is now ready!, $name.', isError: false);
      
      // Navigate back to the AuthStreamWrapper (which will redirect to Home)
      if (mounted) {
        Navigator.of(context).pop();
      }

    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('Firebase Auth Error: ${e.code} - ${e.message}');
      }
      String message;
      switch (e.code) {
        case 'weak-password':
          message = 'The password provided is too weak.';
          break;
        case 'email-already-in-use':
          message = 'An account already exists for that email.';
          break;
        case 'invalid-email':
          message = 'The email address is not valid.';
          break;
        default:
          message = 'Registration failed. Please check your details.';
      }
      _showSnackBar(message, isError: true);
    } catch (e) {
      if (kDebugMode) {
        print('Unknown Sign Up Error: $e');
      }
      _showSnackBar('An unexpected error occurred.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Helper function to show a consistent SnackBar
  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Helper widget for themed text fields
  Widget _buildThemedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: isPassword,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // App Logo/Icon
              Icon(
                Icons.security_update_good,
                size: 80,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(height: 16),
              const Text(
                'Join SurviveNet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 32),
              
              // Name Input
              _buildThemedTextField(
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
              ),
              
              // Email Input
              _buildThemedTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              
              // Password Input
              _buildThemedTextField(
                controller: _passwordController,
                label: 'Password (min. 6 characters)',
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              
              const SizedBox(height: 24),
              
              // Sign Up Button
              _isLoading
                  ? Center(child: CircularProgressIndicator(color: Theme.of(context).primaryColor))
                  : ElevatedButton(
                      onPressed: _signUpWithEmailAndPassword,
                      child: const Text('Sign Up'),
                    ),
              
              const SizedBox(height: 20),
              
              // Back to Login link
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(
                  // Use a distinct style for navigation link
                  foregroundColor: Colors.black, 
                  backgroundColor: Colors.transparent,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                ),
                child: const Text('Already have an account? Log In'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
