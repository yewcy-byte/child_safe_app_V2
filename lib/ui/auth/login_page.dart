import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'role_selection_page.dart';
import '../parents/parent_dashboard.dart';
import '../child/child_dashboard.dart';
import '../../services/child_account_bootstrap_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ChildAccountBootstrapService _childBootstrapService =
      ChildAccountBootstrapService();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _deriveUsername(User user) {
    final email = user.email?.trim() ?? '';
    if (email.contains('@')) {
      final localPart = email.split('@').first.trim();
      if (localPart.isNotEmpty) {
        return localPart;
      }
    }

    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }

    return user.uid;
  }

  Future<void> _syncUsername(User user) async {
    final username = _deriveUsername(user);
    final userRef = _firestore.collection('users').doc(user.uid);
    final userDoc = await userRef.get();
    final currentName = (userDoc.data()?['name'] as String?)?.trim();

    final updates = <String, dynamic>{
      'username': username,
      'email': user.email ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!userDoc.exists) {
      updates['name'] = username;
      updates['createdAt'] = FieldValue.serverTimestamp();
      updates['role'] = '';
    } else if (currentName == null || currentName.isEmpty) {
      updates['name'] = username;
      final existingRole = userDoc.data()?['role'];
      if (existingRole == null) {
        updates['role'] = '';
      }
    }

    await userRef.set(updates, SetOptions(merge: true));
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final UserCredential userCredential = await FirebaseAuth.instance
          .signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        await _syncUsername(user);
        await _navigateBasedOnUserStatus(user.uid);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      UserCredential userCredential;

      if (_isLogin) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );
      }

      if (userCredential.user != null) {
        await _syncUsername(userCredential.user!);
        await _navigateBasedOnUserStatus(userCredential.user!.uid);
      }
    } on FirebaseAuthException catch (e) {
      String message = 'An error occurred';
      if (e.code == 'user-not-found') {
        message = 'No user found with this email';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already in use';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak';
      } else {
        message = 'Error: ${e.message}';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _navigateBasedOnUserStatus(String userId) async {
    try {
      final userRef = _firestore.collection('users').doc(userId);
      final userDoc = await userRef.get();
      final data = userDoc.data();
      final role = (data?['role'] as String?)?.trim().toLowerCase();

      if (!mounted) return;

      if (role == 'parent') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ParentDashboard()),
        );
        return;
      }

      if (role == 'child') {
        await _childBootstrapService.ensureChildStructure(userId);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChildDashboard()),
        );
        return;
      }

      if (data == null || !data.containsKey('role')) {
        await userRef.set({
          'role': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => RoleSelectionPage(userId: userId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading dashboard: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child Safe App')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _isLogin ? 'Sign In' : 'Register',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (!_isLogin && value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _signInWithEmail,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(_isLogin ? 'Sign In' : 'Register'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                    });
                  },
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Register"
                        : 'Already have an account? Sign In',
                  ),
                ),
                const SizedBox(height: 24),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR'),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _signInWithGoogle(context),
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
