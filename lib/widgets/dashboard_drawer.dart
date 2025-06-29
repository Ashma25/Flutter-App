import 'package:flutter/material.dart';
import '../screens/app_theme.dart';
import '../screens/view_profile_page.dart';
import '../screens/animated_login_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DashboardDrawer extends StatefulWidget {
  final VoidCallback? onThemeChanged;
  final String? userEmail;
  final String? userName;

  const DashboardDrawer({
    Key? key,
    this.onThemeChanged,
    this.userEmail,
    this.userName,
  }) : super(key: key);

  @override
  State<DashboardDrawer> createState() => _DashboardDrawerState();
}

class _DashboardDrawerState extends State<DashboardDrawer> {
  String? userName;
  String? userEmail;

  @override
  void initState() {
    super.initState();
    userName = widget.userName;
    userEmail = widget.userEmail;
    if (userName == null && userEmail != null) {
      _fetchUserName();
    }
  }

  Future<void> _fetchUserName() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: userEmail)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        setState(() {
          userName = snapshot.docs.first.data()['name'] as String?;
        });
      }
    } catch (e) {
      print("Error fetching user name: $e");
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(
            color: Color(0xFF2C3E50),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2C3E50),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C3E50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      // Set isLoggedIn to false in Firestore for this user
      if (userEmail != null) {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: userEmail)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(query.docs.first.id)
              .update({'isLoggedIn': false});
        }
      }
      await _signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AnimatedLoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      print('Error signing out: $e');
    }
  }

  void _toggleTheme() {
    AppTheme.setThemeMode(
      AppTheme.isDarkMode ? ThemeMode.light : ThemeMode.dark,
    );
    if (widget.onThemeChanged != null) {
      widget.onThemeChanged!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // User header
          UserAccountsDrawerHeader(
            accountName: Text(userName ?? 'User'),
            accountEmail: Text(userEmail ?? ''),
            currentAccountPicture: CircleAvatar(
              backgroundColor: colorScheme.onPrimary,
              child: Text(
                (userName ?? 'U')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 40.0,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF1976D2),
            ),
          ),

          // Navigation items
          ListTile(
            leading: const Icon(Icons.person_outline, color: Color(0xFF2E2E2E)),
            title: const Text('View Profile'),
            onTap: () {
              Navigator.pop(context);
              if (userEmail != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ViewProfilePage(email: userEmail!),
                  ),
                );
              }
            },
          ),

          ListTile(
            leading: const Icon(Icons.home, color: Color(0xFF2E2E2E)),
            title: const Text('Back to Dashboard'),
            onTap: () {
              Navigator.pop(context);
              // This will close the drawer and stay on current dashboard
            },
          ),

          const Divider(),

          // Theme toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.brightness_6, color: Color(0xFF2E2E2E)),
                const SizedBox(width: 12),
                Expanded(
                  child: ToggleButtons(
                    isSelected: [
                      AppTheme.themeMode == ThemeMode.light,
                      AppTheme.themeMode == ThemeMode.dark,
                      AppTheme.themeMode == ThemeMode.system,
                    ],
                    onPressed: (index) {
                      ThemeMode mode = ThemeMode.light;
                      if (index == 1) mode = ThemeMode.dark;
                      if (index == 2) mode = ThemeMode.system;
                      AppTheme.setThemeMode(mode);
                      if (widget.onThemeChanged != null) widget.onThemeChanged!();
                    },
                    borderRadius: BorderRadius.circular(8),
                    selectedColor: Colors.white,
                    fillColor: const Color(0xFF1976D2),
                    color: const Color(0xFF1976D2),
                    children: const [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Light'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Dark'),
                      ),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('System'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Color(0xFFD32F2F)),
            title: const Text('Logout'),
            onTap: _logout,
          ),
        ],
      ),
    );
  }
}