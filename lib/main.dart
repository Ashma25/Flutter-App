import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'common/animated_login_screen.dart';
import 'common/dashboard_page.dart';
import 'Admin/code_master_page.dart';
import 'common/profile_page.dart';
import 'Admin/admin_employee_masters.dart';
import 'Employee/employee_profile_page.dart';
import 'common/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  // Check for logged-in user
  final query = await FirebaseFirestore.instance
      .collection('users')
      .where('isLoggedIn', isEqualTo: true)
      .limit(1)
      .get();

  Widget homeWidget;
  if (query.docs.isNotEmpty) {
    final userData = query.docs.first.data();
    homeWidget = DashboardPage(email: userData['email']);
  } else {
    homeWidget = const AnimatedLoginScreen();
  }

  runApp(MyApp(homeWidget: homeWidget));
}

class MyApp extends StatefulWidget {
  final Widget homeWidget;
  const MyApp({required this.homeWidget, super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Listen for theme changes
    AppTheme().addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppTheme().removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {
      // Rebuild the app when theme changes
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Employee Management System',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: AppTheme.themeMode,
      home: widget.homeWidget,
      debugShowCheckedModeBanner: false,
      routes: {
        '/codeMaster': (context) {
          final args = ModalRoute.of(context)!.settings.arguments
          as Map<String, dynamic>?;
          return CodeMasterPage(
            email: args?['email'] ?? '',
            role: args?['role'],
          );
        },
        '/employeeProfile': (context) {
          final email = ModalRoute.of(context)!.settings.arguments as String?;
          return EmployeeProfilePage(
            loggedInUserEmail: email ?? '',
            employeeData: const {}, // Pass empty map or fetch data if needed
          );
        },
        '/employeeMaster': (context) {
          final email = ModalRoute.of(context)!.settings.arguments as String?;
          return EmployeeProfilePage(
            loggedInUserEmail: email ?? '',
            employeeData: const {}, // Or fetch and pass actual data if needed
          );
        },
      },
    );
  }
}