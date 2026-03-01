import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'models/hive/app_usage_cache.dart';
import 'models/hive/screen_time_cache.dart';
import 'services/child_account_bootstrap_service.dart';
import 'services/location_request_foreground_service.dart';
import 'ui/shared/shared.dart';
import 'ui/auth/auth.dart';
import 'ui/parents/parent_dashboard.dart';
import 'ui/child/child.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
  }

  await LocationRequestForegroundService.initialize();

  // Initialize Hive for local caching
  await Hive.initFlutter();
  
  // Register Hive adapters
  Hive.registerAdapter(ScreenTimeCacheAdapter());
  Hive.registerAdapter(AppUsageCacheAdapter());
  Hive.registerAdapter(AppUsageCacheListAdapter());

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final ChildAccountBootstrapService _childBootstrapService =
      ChildAccountBootstrapService();

  Future<Widget> _resolveHomeForUser(String userId) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final userDoc = await userRef.get();
    final data = userDoc.data();
    final role = (data?['role'] as String?)?.trim().toLowerCase();

    if (role == 'parent') {
      return ParentDashboard();
    }

    if (role == 'child') {
      await _childBootstrapService.ensureChildStructure(userId);
      return ChildDashboard();
    }

    if (data == null || !data.containsKey('role')) {
      await userRef.set({
        'role': '',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    return RoleSelectionPage(userId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Child Safe App',
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          
          if (!snapshot.hasData) {
            return LoginPage();
          }

          return FutureBuilder<Widget>(
            future: _resolveHomeForUser(snapshot.data!.uid),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              if (!userSnapshot.hasData) {
                return LoginPage();
              }

              return userSnapshot.data!;
            },
          );
        },
      ),
    );
  }
}