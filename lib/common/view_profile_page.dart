import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../Admin/edit_profile_page.dart';
import 'dart:ui';
import 'animated_login_screen.dart';
import '../widgets/dashboard_drawer.dart';

class ViewProfilePage extends StatefulWidget {
  final String email;

  const ViewProfilePage({
    super.key,
    required this.email,
  });

  @override
  State<ViewProfilePage> createState() => _ViewProfilePageState();
}

class _ViewProfilePageState extends State<ViewProfilePage> {
  Map<String, dynamic>? userData;
  bool isLoading = true;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    fetchUserData();
  }

  Future<void> fetchUserData() async {
    try {
      setState(() {
        isLoading = true;
      });

      final snapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        setState(() {
          userData = data;
          isLoading = false;
        });
      } else {
        setState(() {
          isLoading = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User profile not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      print("Error fetching user data: $e");
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  String getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  String formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Not provided';
    if (timestamp is Timestamp) {
      return DateFormat('MMMM d, yyyy').format(timestamp.toDate());
    }
    return timestamp.toString();
  }

  String formatPhone(dynamic phone) {
    if (phone == null) return 'Not provided';
    if (phone is num) {
      return phone.toString();
    }
    return phone.toString();
  }

  Future<void> _navigateToEditProfile() async {
    if (userData == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfilePage(
          email: widget.email,
          userData: userData!,
        ),
      ),
    );
    if (result == true) {
      fetchUserData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onPrimary),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Profile',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.primary,
        actions: [
          IconButton(
            icon: Icon(Icons.edit, color: colorScheme.onPrimary),
            onPressed: _navigateToEditProfile,
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onPrimary),
            onPressed: fetchUserData,
          ),
        ],
      ),
      drawer: DashboardDrawer(
        onThemeChanged: () {
          setState(() {});
        },
        userEmail: widget.email,
        userName: userData?['name'],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : userData == null
          ? Center(
        child: Text(
          'No user data found',
          style: TextStyle(color: colorScheme.onSurface),
        ),
      )
          : AnimatedBuilder(
        animation: Listenable.merge([]), // No animation, just for structure
        builder: (context, child) {
          return Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: MediaQuery.of(context).size,
                painter: AnimatedWaveBackgroundPainter(0, colorScheme),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        width: 500,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 40,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.10),
                              blurRadius: 36,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Column(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: colorScheme.primary.withOpacity(0.3),
                                          blurRadius: 10,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: CircleAvatar(
                                      radius: 50,
                                      backgroundColor: colorScheme.primary,
                                      child: Text(
                                        getInitials(userData!['name']?.toString()),
                                        style: TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    userData!['name']?.toString() ?? 'No Name',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    userData!['email']?.toString() ?? 'No Email',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colorScheme.onSurface.withOpacity(0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    _buildInfoRow(
                                      'Name',
                                      Text(
                                        userData!['name']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Email',
                                      Text(
                                        userData!['email']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Phone',
                                      Text(
                                        formatPhone(userData!['phone']),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Gender',
                                      Text(
                                        userData!['gender']?.toString().toUpperCase() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Date of Birth',
                                      Text(
                                        formatTimestamp(userData!['dob']),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Address',
                                      Text(
                                        userData!['address']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'User ID',
                                      Text(
                                        userData!['userId']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Designation',
                                      Text(
                                        userData!['designation']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Role',
                                      Text(
                                        userData!['role']?.toString().toUpperCase() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Joining Date',
                                      Text(
                                        formatTimestamp(userData!['joiningDate']),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    _buildDivider(colorScheme),
                                    _buildInfoRow(
                                      'Created By',
                                      Text(
                                        userData!['createdBy']?.toString() ?? 'Not provided',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(String label, Widget valueWidget) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
            ),
          ),
          Expanded(child: valueWidget),
        ],
      ),
    );
  }

  Widget _buildDivider(ColorScheme colorScheme) {
    return Divider(color: colorScheme.onSurface.withOpacity(0.1), height: 1);
  }

  Future<void> logout(BuildContext context, String email) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(query.docs.first.id)
          .update({'isLoggedIn': false});
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AnimatedLoginScreen()),
          (route) => false,
    );
  }
}