import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_employee_masters.dart';
import '../widgets/dashboard_drawer.dart';

class ProfilePage extends StatefulWidget {
  final String email;
  final bool isViewOnly;

  const ProfilePage({super.key, required this.email, this.isViewOnly = false});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  bool _isEditing = false;
  String? _name;
  String? _userId;
  String? _role;
  String? _phone;
  Timestamp? _dob;
  String? _address;
  String? _designation;
  Timestamp? _joiningDate;
  String? _status;
  String? _gender;
  String? _createdBy;
  Timestamp? _createdOn;
  String? _updatedBy;
  Timestamp? _updatedOn;
  String? _profileImageUrl;
  String? selectedDepartment;
  List<String> departments = ['Department 1', 'Department 2', 'Department 3'];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        setState(() {
          _name = data['name'];
          _userId = data['userId']?.toString();
          _role = data['role'];
          _phone = data['phone']?.toString();
          _dob = data['dob'];
          _address = data['address'];
          _designation = data['designation'];
          _joiningDate = data['joiningDate'];
          _status = data['status'];
          _gender = data['gender'];
          _createdBy = data['createdBy'];
          _createdOn = data['createdOn'];
          _updatedBy = data['updatedBy'];
          _updatedOn = data['updatedOn'];
          _profileImageUrl = data['profileImageUrl'];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Not set';
    final date = timestamp.toDate();
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildProfileField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });
  }

  Future<void> _saveChanges() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final docRef = querySnapshot.docs.first.reference;
        await docRef.update({
          'name': _name,
          'phone': _phone,
          'address': _address,
          'updatedBy': widget.email,
          'updatedOn': FieldValue.serverTimestamp(),
        });

        setState(() {
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      drawer: DashboardDrawer(
        onThemeChanged: () {
          setState(() {});
        },
        userEmail: widget.email,
      ),
      backgroundColor: colorScheme.surface,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_profileImageUrl != null)
                Center(
                  child: CircleAvatar(
                    radius: 48,
                    backgroundImage: NetworkImage(_profileImageUrl!),
                  ),
                ),
              const SizedBox(height: 24),
              _buildProfileField('Name', _name ?? ''),
              _buildProfileField('User ID', _userId ?? ''),
              _buildProfileField('Role', _role ?? ''),
              _buildProfileField('Phone', _phone ?? ''),
              _buildProfileField('Date of Birth', _formatDate(_dob)),
              _buildProfileField('Address', _address ?? ''),
              _buildProfileField('Designation', _designation ?? ''),
              _buildProfileField(
                  'Joining Date', _formatDate(_joiningDate)),
              _buildProfileField('Status', _status ?? ''),
              _buildProfileField('Gender', _gender ?? ''),
            ],
          ),
        ),
      ),
    );
  }
}

class AnimatedWaveBackgroundPainter extends CustomPainter {
  final double wavePhase;
  final ColorScheme colorScheme;

  AnimatedWaveBackgroundPainter(this.wavePhase, this.colorScheme);

  @override
  void paint(Canvas canvas, Size size) {
    final List<Color> waveColors = [
      colorScheme.primary.withOpacity(0.18),
      colorScheme.secondary.withOpacity(0.13),
      colorScheme.primary.withOpacity(0.10),
    ];

    for (int i = 0; i < 3; i++) {
      final path = Path();
      final amplitude = 18.0 + i * 10;
      final frequency = 1.5 + i * 0.5;
      final yOffset = size.height * (0.65 + i * 0.08);
      path.moveTo(0, yOffset);

      for (double x = 0; x <= size.width; x += 1) {
        final y = amplitude *
            sin((x / size.width * 2 * pi * frequency) + wavePhase + i) +
            yOffset;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final paint = Paint()..color = waveColors[i];
      canvas.drawPath(path, paint);
    }

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final gradient = LinearGradient(
      colors: [
        colorScheme.surface,
        colorScheme.primary.withOpacity(0.7),
        colorScheme.secondary.withOpacity(0.5),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}