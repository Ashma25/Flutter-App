import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'view_profile_page.dart';
import 'edit_profile_page.dart';

class AdminEmployeeMasterPage extends StatefulWidget {
  final String userEmail;

  const AdminEmployeeMasterPage({Key? key, required this.userEmail})
      : super(key: key);

  @override
  State<AdminEmployeeMasterPage> createState() =>
      _AdminEmployeeMasterPageState();
}

class _AdminEmployeeMasterPageState extends State<AdminEmployeeMasterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _userIdController = TextEditingController();
  String? _selectedGender;
  String _selectedRole = 'Employee';
  String _selectedStatus = 'Active';
  String? _selectedDesignation;
  String? _selectedDepartment;
  DateTime _selectedDateOfBirth = DateTime.now();
  DateTime _selectedDateOfJoining = DateTime.now();
  bool _isLoading = true;
  bool _isAdmin = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _designationCodes = [];
  List<Map<String, dynamic>> _departmentCodes = [];
  List<Map<String, dynamic>> _genderCodes = [];

  String getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _checkAdminStatus();
    _loadUsers();
    _loadDesignations();
    _loadDepartments();
    _loadGenders();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _userIdController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
  }

  Future<void> _checkAdminStatus() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data();
        final isAdmin = userData['role']?.toString().toLowerCase() == 'admin';

        if (mounted) {
          setState(() {
            _isAdmin = isAdmin;
            _isLoading = false;
          });

          if (!isAdmin) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Access denied. Admin privileges required.'),
                backgroundColor: Colors.red,
              ),
            );
            Navigator.pop(context);
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isAdmin = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User not found'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAdmin = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking admin status: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadUsers() async {
    try {
      setState(() => _isLoading = true);
      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .orderBy('name')
          .get();

      final List<Map<String, dynamic>> users = querySnapshot.docs
          .map((doc) => {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      })
          .toList();

      setState(() {
        _users = users;
        _filteredUsers = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading users: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadDesignations() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'designation')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _designationCodes = querySnapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'Value1': data['Value1'],
            'description': data['Long Description'],
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading designations: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadDepartments() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'department')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _departmentCodes = querySnapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading departments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadGenders() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'gender')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _genderCodes = querySnapshot.docs.map((doc) {
          final data = doc.data();
          return <String, dynamic>{
            'id': doc.id,
            'Value1': data['Value1'],
            'description': data['Long Description'],
          };
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading genders: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredUsers = _users;
      } else {
        _filteredUsers = _users.where((user) {
          final name = user['name']?.toString().toLowerCase() ?? '';
          final email = user['email']?.toString().toLowerCase() ?? '';
          final role = user['role']?.toString().toLowerCase() ?? '';
          final designation =
              user['designation']?.toString().toLowerCase() ?? '';
          final searchLower = query.toLowerCase();

          return name.contains(searchLower) ||
              email.contains(searchLower) ||
              role.contains(searchLower) ||
              designation.contains(searchLower);
        }).toList();
      }
    });
  }

  Future<void> _showUserForm([Map<String, dynamic>? user]) async {
    final isEditing = user != null;
    _nameController.text = user?['name']?.toString() ?? '';
    _emailController.text = user?['email']?.toString() ?? '';
    _phoneController.text = user?['phone']?.toString() ?? '';
    _addressController.text = user?['address']?.toString() ?? '';
    _selectedDesignation = user?['designation']?.toString();
    _selectedDepartment = user?['department']?.toString();
    _selectedGender = user?['gender']?.toString();
    _selectedRole = user?['role']?.toString() ?? 'Employee';
    _selectedStatus = user?['status']?.toString() ?? 'Active';
    _selectedDateOfBirth = user?['dateOfBirth'] != null
        ? (user?['dateOfBirth'] as Timestamp).toDate()
        : DateTime.now();
    _selectedDateOfJoining = user?['dateOfJoining'] != null
        ? (user?['dateOfJoining'] as Timestamp).toDate()
        : DateTime.now();

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isEditing ? 'Edit Employee' : 'Add Employee', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
            minWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return IntrinsicWidth(
                  stepWidth: constraints.maxWidth,
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTextField(_nameController, 'Full Name', required: true),
                        const SizedBox(height: 16),
                        _buildTextField(_emailController, 'Email', keyboardType: TextInputType.emailAddress, required: true),
                        const SizedBox(height: 16),
                        _buildTextField(_phoneController, 'Phone Number', keyboardType: TextInputType.phone, required: true),
                        const SizedBox(height: 16),
                        _buildTextField(_addressController, 'Address', required: true),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedDesignation,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Designation',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.work_outline),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Select Designation'),
                            ),
                            ..._designationCodes.map((designation) {
                              return DropdownMenuItem<String>(
                                value: designation['Value1'],
                                child: Text(designation['Value1'] ?? ''),
                              );
                            }).toList(),
                          ],
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedDesignation = newValue;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select designation';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedDepartment,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Department',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.business),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Select Department'),
                            ),
                            ..._departmentCodes.map((department) {
                              return DropdownMenuItem<String>(
                                value: department['Value1'],
                                child: Text(department['Value1'] ?? ''),
                              );
                            }).toList(),
                          ],
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedDepartment = newValue;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select department';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          value: _selectedGender,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Gender',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('Select Gender'),
                            ),
                            ..._genderCodes.map((gender) {
                              return DropdownMenuItem<String>(
                                value: gender['Value1'],
                                child: Text(gender['Value1'] ?? ''),
                              );
                            }).toList(),
                          ],
                          onChanged: (String? newValue) {
                            setState(() {
                              _selectedGender = newValue;
                            });
                          },
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please select gender';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(_userIdController, 'User ID', required: true),
                        const SizedBox(height: 16),
                        _buildTextField(TextEditingController(text: _selectedRole), 'Role', required: true),
                        const SizedBox(height: 16),
                        _buildTextField(TextEditingController(text: _selectedStatus), 'Status', required: true),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                title: const Text('Date of Birth'),
                                subtitle: Text(
                                  '${_selectedDateOfBirth.day}/${_selectedDateOfBirth.month}/${_selectedDateOfBirth.year}',
                                ),
                                trailing: const Icon(Icons.calendar_today),
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDateOfBirth,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setState(() => _selectedDateOfBirth = date);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                title: const Text('Date of Joining'),
                                subtitle: Text(
                                  '${_selectedDateOfJoining.day}/${_selectedDateOfJoining.month}/${_selectedDateOfJoining.year}',
                                ),
                                trailing: const Icon(Icons.calendar_today),
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: _selectedDateOfJoining,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setState(() => _selectedDateOfJoining = date);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final userData = {
                    'name': _nameController.text,
                    'email': _emailController.text,
                    'phone': _phoneController.text,
                    'address': _addressController.text,
                    'designation': _selectedDesignation,
                    'department': _selectedDepartment,
                    'gender': _selectedGender,
                    'role': _selectedRole,
                    'status': _selectedStatus,
                    'dateOfBirth': Timestamp.fromDate(_selectedDateOfBirth),
                    'dateOfJoining': Timestamp.fromDate(_selectedDateOfJoining),
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdBy': widget.userEmail,
                    'updatedAt': FieldValue.serverTimestamp(),
                    'updatedBy': widget.userEmail,
                  };

                  if (!isEditing) {
                    final userId = _userIdController.text.trim();
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .set({
                      ...userData,
                      'userId': userId,
                    });
                  } else {
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user['id'])
                        .update(userData);
                  }

                  Navigator.pop(context);
                  _loadUsers();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error saving user: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: Text(isEditing ? 'Update' : 'Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showUserDetails(Map<String, dynamic> user) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Employee Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow('Name', user['name']?.toString() ?? ''),
              _buildInfoRow('Email', user['email']?.toString() ?? ''),
              _buildInfoRow('Phone', user['phone']?.toString() ?? ''),
              _buildInfoRow('Gender', user['gender']?.toString() ?? ''),
              _buildInfoRow('Department', user['department']?.toString() ?? ''),
              _buildInfoRow('Designation', user['designation']?.toString() ?? ''),
              _buildInfoRow('Role', user['role']?.toString() ?? ''),
              _buildInfoRow('Status', user['status']?.toString() ?? ''),
              _buildInfoRow(
                'Date of Birth',
                user['dateOfBirth'] != null
                    ? DateFormat('yyyy-MM-dd')
                    .format(user['dateOfBirth'].toDate())
                    : '',
              ),
              _buildInfoRow(
                'Date of Joining',
                user['dateOfJoining'] != null
                    ? DateFormat('yyyy-MM-dd')
                    .format(user['dateOfJoining'].toDate())
                    : '',
              ),
              _buildInfoRow('Address', user['address']?.toString() ?? ''),
              _buildInfoRow(
                  'Created By', user['createdBy']?.toString() ?? 'System'),
              _buildInfoRow(
                'Created On',
                user['createdAt'] != null
                    ? DateFormat('yyyy-MM-dd HH:mm')
                    .format(user['createdAt'].toDate())
                    : '',
              ),
              _buildInfoRow(
                  'Updated By', user['updatedBy']?.toString() ?? 'System'),
              _buildInfoRow(
                'Updated On',
                user['updatedAt'] != null
                    ? DateFormat('yyyy-MM-dd HH:mm')
                    .format(user['updatedAt'].toDate())
                    : '',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? 'N/A' : value),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteEmployee(String userId) async {
    // Show confirmation dialog
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text(
              'Are you sure you want to delete this employee? This action cannot be undone.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        setState(() => _isLoading = true);
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Employee deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadUsers(); // Refresh the list after deletion
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting employee: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Employee Master (Admin)',
          style: TextStyle(color: colorScheme.onPrimary),
        ),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Search employees...',
                hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                prefixIcon: Icon(Icons.search, color: colorScheme.onSurface),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
              onChanged: _filterUsers,
            ),
          ),
          Expanded(
            child: _filteredUsers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search_off,
                    size: 64,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No employees found',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _searchQuery.isEmpty
                        ? 'Add employees to get started'
                        : 'Try adjusting your search',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filteredUsers.length,
              itemBuilder: (context, index) {
                final user = _filteredUsers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: colorScheme.surface,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(8),
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      child: Text(getInitials(user['name'])),
                    ),
                    title: Text(
                      user['name'] ?? 'No Name',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['designation'] ?? 'No Designation',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                        Text(
                          user['email'] ?? 'No Email',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        if (value == 'view') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ViewProfilePage(email: user['email']),
                            ),
                          );
                        } else if (value == 'edit') {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EditProfilePage(
                                email: user['email'],
                                userData: user,
                              ),
                            ),
                          ).then((result) {
                            if (result == true) _loadUsers();
                          });
                        } else if (value == 'delete') {
                          _deleteEmployee(user['id']);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('View Profile'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit Profile'),
                        ),
                        if (user['email'] != widget.userEmail)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserForm(),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _clearControllers() {
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _addressController.clear();
    _selectedDesignation = null;
    _selectedDepartment = null;
    _selectedGender = null;
    _selectedRole = 'Employee';
    _selectedStatus = 'Active';
    _selectedDateOfBirth = DateTime.now();
    _selectedDateOfJoining = DateTime.now();
    _userIdController.clear();
  }

  Widget _buildTextField(TextEditingController controller, String label, {TextInputType keyboardType = TextInputType.text, bool required = false}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        label: required
            ? RichText(
          text: TextSpan(
            text: label,
            style: TextStyle(color: Colors.grey[700]),
            children: const [
              TextSpan(
                text: ' *',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        )
            : Text(label),
        border: const OutlineInputBorder(),
      ),
      keyboardType: keyboardType,
      validator: required
          ? (value) {
        if (value == null || value.trim().isEmpty) {
          return 'This field is required';
        }
        return null;
      }
          : null,
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
      final yOffset = size.height * (0.65 + i * 0.06);

      path.moveTo(0, yOffset);

      for (double x = 0; x <= size.width; x++) {
        final y = amplitude *
            sin((frequency * (x / size.width) * 2 * pi) + wavePhase + i) +
            yOffset;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      final paint = Paint()..color = waveColors[i];
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant AnimatedWaveBackgroundPainter oldDelegate) =>
      oldDelegate.wavePhase != wavePhase;
}

class AdminLeaveCalendarPage extends StatefulWidget {
  const AdminLeaveCalendarPage({super.key});

  @override
  State<AdminLeaveCalendarPage> createState() => _AdminLeaveCalendarPageState();
}

class _AdminLeaveCalendarPageState extends State<AdminLeaveCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = true;
  String _statusFilter = 'all'; // 'all', 'approved', 'pending', 'rejected'
  final Map<String, Color> _statusColors = {
    'approved': Colors.green,
    'pending': Colors.orange,
    'rejected': Colors.red,
  };

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      setState(() => _isLoading = true);

      // Load company holidays
      final holidaysSnapshot = await FirebaseFirestore.instance
          .collection('Leave Calendar')
          .where('Active', isEqualTo: 'Yes')
          .get();

      // Load all leaves
      final leavesSnapshot = await FirebaseFirestore.instance
          .collection('leaves')
          .get();

      final Map<DateTime, List<Map<String, dynamic>>> events = {};

      // Process company holidays
      for (var doc in holidaysSnapshot.docs) {
        final data = doc.data();
        DateTime holidayDate;
        if (data['holidayDate'] is Timestamp) {
          holidayDate = (data['holidayDate'] as Timestamp).toDate();
        } else if (data['holidayDate'] is String) {
          holidayDate = DateTime.tryParse(data['holidayDate'] as String) ??
              DateTime.now();
        } else {
          continue;
        }
        final date = DateTime(holidayDate.year, holidayDate.month, holidayDate.day);
        if (!events.containsKey(date)) {
          events[date] = [];
        }
        events[date]!.add({
          'type': 'company_holiday',
          'name': data['holidayName'],
          'color': Colors.blue,
          'description': 'Company Holiday',
        });
      }

      // Process employee leaves
      for (var doc in leavesSnapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? 'pending').toLowerCase();

        // Skip if not matching filter
        if (_statusFilter != 'all' && status != _statusFilter) continue;

        final startDate = (data['startDate'] is Timestamp)
            ? (data['startDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['startDate'].toString()) ?? DateTime.now();
        final endDate = (data['endDate'] is Timestamp)
            ? (data['endDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['endDate'].toString()) ?? DateTime.now();

        for (var date = startDate;
        date.isBefore(endDate.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
          final normalizedDate = DateTime(date.year, date.month, date.day);
          if (!events.containsKey(normalizedDate)) {
            events[normalizedDate] = [];
          }
          events[normalizedDate]!.add({
            'type': 'leave',
            'id': doc.id,
            'name': data['leaveType'] ?? 'Leave',
            'color': _statusColors[status] ?? Colors.grey,
            'status': status,
            'email': data['email'],
            'reason': data['reason'],
            'startDate': startDate,
            'endDate': endDate,
            ...data,
          });
        }
      }

      setState(() {
        _events = events;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading calendar events: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  void _showDayEvents(DateTime day) {
    final events = _getEventsForDay(day);
    if (events.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(DateFormat('MMMM dd, yyyy').format(day)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];
              if (event['type'] == 'company_holiday') {
                return ListTile(
                  leading: const Icon(Icons.event, color: Colors.blue),
                  title: Text(event['name']),
                  subtitle: const Text('Company Holiday'),
                );
              } else {
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      Icons.event,
                      color: event['color'],
                    ),
                    title: Text(event['name']),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Employee: ${event['email']}'),
                        Text('Status: ${event['status'].toUpperCase()}'),
                        if (event['reason'] != null)
                          Text('Reason: ${event['reason']}'),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () {
                            Navigator.pop(context);
                            _showEditLeaveDialog(event);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteLeave(event['id']);
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditLeaveDialog(Map<String, dynamic> leave) async {
    String? newStatus = leave['status'];
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Leave Status'),
        content: DropdownButton<String>(
          value: newStatus,
          items: ['approved', 'pending', 'rejected']
              .map((status) => DropdownMenuItem(
            value: status,
            child: Text(status.toUpperCase()),
          ))
              .toList(),
          onChanged: (value) {
            newStatus = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (newStatus != null && newStatus != leave['status']) {
                try {
                  await FirebaseFirestore.instance
                      .collection('leaves')
                      .doc(leave['id'])
                      .update({'status': newStatus});
                  Navigator.pop(context);
                  _loadEvents(); // Reload events after update
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error updating leave status: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLeave(String leaveId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Leave'),
        content: const Text('Are you sure you want to delete this leave record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance
            .collection('leaves')
            .doc(leaveId)
            .delete();
        _loadEvents(); // Reload events after deletion
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting leave: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leave Calendar'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _statusFilter = value;
                _loadEvents();
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'all',
                child: Text('All Leaves'),
              ),
              const PopupMenuItem(
                value: 'approved',
                child: Text('Approved'),
              ),
              const PopupMenuItem(
                value: 'pending',
                child: Text('Pending'),
              ),
              const PopupMenuItem(
                value: 'rejected',
                child: Text('Rejected'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Text(_statusFilter.toUpperCase()),
                  const Icon(Icons.filter_list),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              _showDayEvents(selectedDay);
            },
            calendarStyle: const CalendarStyle(
              markersMaxCount: 3,
            ),
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return null;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: events.take(3).map((event) {
                    final color = (event as Map<String, dynamic>)['color'] as Color;
                    return Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            eventLoader: _getEventsForDay,
          ),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.circle, color: Colors.blue, size: 12),
                SizedBox(width: 4),
                Text('Holiday'),
                SizedBox(width: 16),
                Icon(Icons.circle, color: Colors.green, size: 12),
                SizedBox(width: 4),
                Text('Approved'),
                SizedBox(width: 16),
                Icon(Icons.circle, color: Colors.orange, size: 12),
                SizedBox(width: 4),
                Text('Pending'),
                SizedBox(width: 16),
                Icon(Icons.circle, color: Colors.red, size: 12),
                SizedBox(width: 4),
                Text('Rejected'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> uploadUserData({
  required String name,
  required int userId,
  required String role,
  required String email,
  required int phone,
  required DateTime dob,
  required String address,
  required String designation,
  required DateTime joiningDate,
  required String status,
  required String gender,
  required String createdBy,
  required DateTime createdOn,
  required String updatedBy,
  required DateTime updatedOn,
  required String password,
}) async {
  await FirebaseFirestore.instance.collection('users').add({
    'name': name,
    'userId': userId,
    'role': role,
    'email': email,
    'phone': phone,
    'dob': Timestamp.fromDate(dob),
    'address': address,
    'designation': designation,
    'joiningDate': Timestamp.fromDate(joiningDate),
    'status': status,
    'gender': gender,
    'createdBy': createdBy,
    'createdOn': Timestamp.fromDate(createdOn),
    'updatedBy': updatedBy,
    'updatedOn': Timestamp.fromDate(updatedOn),
    'password': password,
  });
}

Future<Map<String, dynamic>?> fetchUserData(String userId) async {
  final query = await FirebaseFirestore.instance
      .collection('users')
      .where('userId', isEqualTo: userId)
      .limit(1)
      .get();

  if (query.docs.isNotEmpty) {
    return query.docs.first.data();
  }
  return null;
}

class ThemedScaffold extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;
  final FloatingActionButton? floatingActionButton;

  const ThemedScaffold({
    Key? key,
    required this.child,
    this.appBar,
    this.floatingActionButton,
  }) : super(key: key);

  static const ColorScheme colorScheme = ColorScheme.light(
    primary: Color(0xFF1976D2),
    onPrimary: Colors.white,
    surface: Color(0xFFF5F7FA),
    onSurface: Color(0xFF2E2E2E),
    secondary: Color(0xFF64B5F6),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: AnimatedWaveBackgroundPainter(0, colorScheme),
          ),
          child,
        ],
      ),
    );
  }
}