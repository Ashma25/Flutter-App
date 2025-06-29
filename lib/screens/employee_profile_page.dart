import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_profile_page.dart';

class EmployeeProfilePage extends StatefulWidget {
  final String loggedInUserEmail;
  final Map<String, dynamic> employeeData;
  const EmployeeProfilePage(
      {super.key, required this.loggedInUserEmail, required this.employeeData});

  @override
  State<EmployeeProfilePage> createState() => _EmployeeProfilePageState();
}

class _EmployeeProfilePageState extends State<EmployeeProfilePage> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: widget.loggedInUserEmail)
        .limit(1)
        .get();
    if (snapshot.docs.isNotEmpty) {
      setState(() {
        _data = snapshot.docs.first.data();
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getField(String key, {String fallback = 'Not provided'}) {
    final value = _data?[key];
    if (value == null || value.toString().isEmpty) return fallback;
    if (key == 'role') return value.toString().toUpperCase();
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('My Profile', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            tooltip: 'Edit Profile',
            onPressed: _isLoading || _data == null
                ? null
                : () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProfilePage(
                    email: widget.loggedInUserEmail,
                    userData: _data!,
                  ),
                ),
              );
              if (result == true) {
                _fetchProfile();
              }
            },
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFB3C6E7), Color(0xFF1976D2)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: Colors.blue,
                  child: Text(
                    _getField('name', fallback: 'U')[0].toUpperCase(),
                    style: const TextStyle(
                        fontSize: 36,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  _getField('name'),
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 6),
                Text(
                  _getField('email'),
                  style: const TextStyle(
                      fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Container(
                  width: 340,
                  padding: const EdgeInsets.symmetric(
                      vertical: 24, horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.98),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.10),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _profileRow('Name', _getField('name')),
                      _profileRow('Email', _getField('email')),
                      _profileRow('Phone', _getField('phone')),
                      _profileRow('Gender', _getField('gender')),
                      _profileRow('Date of Birth', _getField('dob')),
                      _profileRow('Address', _getField('address')),
                      _profileRow('User ID', _getField('userId')),
                      _profileRow('Designation', _getField('designation')),
                      _profileRow('Role', _getField('role')),
                      _profileRow('Joining Date', _getField('joiningDate')),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _profileRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                      fontSize: 16))),
          const SizedBox(width: 10),
          Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.black87, fontSize: 16))),
        ],
      ),

    );
  }
}