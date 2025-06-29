import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/dashboard_drawer.dart';

class EditProfilePage extends StatefulWidget {
  final String email;
  final Map<String, dynamic> userData;

  const EditProfilePage({
    super.key,
    required this.email,
    required this.userData,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _designationController = TextEditingController();
  final _userIdController = TextEditingController();
  final _roleController = TextEditingController();
  final _emailController = TextEditingController();
  final _joiningDateController = TextEditingController();
  final _createdByController = TextEditingController();
  final _createdOnController = TextEditingController();
  final _updatedByController = TextEditingController();
  final _updatedOnController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedGender = '';
  String _selectedDesignation = '';
  String _selectedDepartment = '';
  DateTime? _selectedDateOfBirth;
  DateTime? _selectedJoiningDate;
  DateTime? _selectedCreatedOn;
  DateTime? _selectedUpdatedOn;
  String _selectedRole = 'Employee';
  String _selectedStatus = 'Active';
  bool _isLoading = false;
  final bool _obscurePassword = true;

  // Code master values
  List<Map<String, dynamic>> _designationCodes = [];
  List<Map<String, dynamic>> _departmentCodes = [];
  List<Map<String, dynamic>> _genderCodes = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadCodeMasterValues();
  }

  Future<void> _loadCodeMasterValues() async {
    try {
      await Future.wait([
        _loadDesignations(),
        _loadDepartments(),
        _loadGenders(),
      ]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading code master values: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadDesignations() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'designation')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _designationCodes = snapshot.docs.map((doc) {
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
      final snapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'department')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _departmentCodes = snapshot.docs.map((doc) {
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
            content: Text('Error loading departments: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadGenders() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'gender')
          .where('Active', isEqualTo: true)
          .get();

      setState(() {
        _genderCodes = snapshot.docs.map((doc) {
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

  void _initializeControllers() {
    _nameController.text = widget.userData['name'] ?? '';
    _userIdController.text = widget.userData['userId']?.toString() ?? '';
    _roleController.text = widget.userData['role'] ?? '';
    _emailController.text = widget.userData['email'] ?? '';
    _phoneController.text = widget.userData['phone']?.toString() ?? '';
    _addressController.text = widget.userData['address'] ?? '';
    _designationController.text = widget.userData['designation'] ?? '';
    _createdByController.text = widget.userData['createdBy'] ?? '';
    _updatedByController.text = widget.userData['updatedBy'] ?? '';
    _passwordController.text = widget.userData['password'] ?? '';
    _selectedRole = widget.userData['role'] ?? 'Employee';
    _selectedStatus = widget.userData['status'] ?? 'Active';
    _selectedDesignation = widget.userData['designation'] ?? '';
    _selectedDepartment = widget.userData['department'] ?? '';
    _selectedGender = widget.userData['gender'] ?? '';

    if (widget.userData['joiningDate'] != null) {
      if (widget.userData['joiningDate'] is Timestamp) {
        _selectedJoiningDate = (widget.userData['joiningDate'] as Timestamp).toDate();
      } else if (widget.userData['joiningDate'] is String) {
        _selectedJoiningDate = DateTime.parse(widget.userData['joiningDate']);
      }
    }
    if (widget.userData['createdOn'] != null) {
      if (widget.userData['createdOn'] is Timestamp) {
        _selectedCreatedOn = (widget.userData['createdOn'] as Timestamp).toDate();
      } else if (widget.userData['createdOn'] is String) {
        _selectedCreatedOn = DateTime.parse(widget.userData['createdOn']);
      }
    }
    if (widget.userData['updatedOn'] != null) {
      if (widget.userData['updatedOn'] is Timestamp) {
        _selectedUpdatedOn = (widget.userData['updatedOn'] as Timestamp).toDate();
      } else if (widget.userData['updatedOn'] is String) {
        _selectedUpdatedOn = DateTime.parse(widget.userData['updatedOn']);
      }
    }
    if (widget.userData['dateOfBirth'] != null) {
      if (widget.userData['dateOfBirth'] is Timestamp) {
        _selectedDateOfBirth = (widget.userData['dateOfBirth'] as Timestamp).toDate();
      } else if (widget.userData['dateOfBirth'] is String) {
        _selectedDateOfBirth = DateTime.parse(widget.userData['dateOfBirth']);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _designationController.dispose();
    _userIdController.dispose();
    _roleController.dispose();
    _emailController.dispose();
    _joiningDateController.dispose();
    _createdByController.dispose();
    _createdOnController.dispose();
    _updatedByController.dispose();
    _updatedOnController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateOfBirth ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDateOfBirth) {
      setState(() {
        _selectedDateOfBirth = picked;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (userQuery.docs.isEmpty) {
        throw Exception('User not found');
      }

      final userDoc = userQuery.docs.first;
      await userDoc.reference.update({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'address': _addressController.text.trim(),
        'designation': _selectedDesignation,
        'department': _selectedDepartment,
        'gender': _selectedGender,
        'dateOfBirth': _selectedDateOfBirth?.toIso8601String(),
        'updatedBy': widget.email,
        'updatedOn': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
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
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTextField(_nameController, 'Full Name'),
              const SizedBox(height: 16),
              _buildTextField(_emailController, 'Email', keyboardType: TextInputType.emailAddress, readOnly: true),
              const SizedBox(height: 16),
              _buildTextField(_phoneController, 'Phone Number'),
              const SizedBox(height: 16),
              _buildTextField(_addressController, 'Address'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDesignation.isEmpty ? null : _selectedDesignation,
                decoration: const InputDecoration(
                  labelText: 'Designation',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work_outline),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Select Designation')),
                  ..._designationCodes.map((designation) {
                    return DropdownMenuItem<String>(
                      value: designation['Value1'],
                      child: Text(designation['Value1'] ?? ''),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedDesignation = value);
                  }
                },
                validator: (value) => value?.isEmpty ?? true ? 'Designation is required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDepartment.isEmpty ? null : _selectedDepartment,
                decoration: const InputDecoration(
                  labelText: 'Department',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Select Department')),
                  ..._departmentCodes.map((department) {
                    return DropdownMenuItem<String>(
                      value: department['Value1'],
                      child: Text(department['Value1'] ?? ''),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedDepartment = value);
                  }
                },
                validator: (value) => value?.isEmpty ?? true ? 'Department is required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedGender.isEmpty ? null : _selectedGender,
                decoration: const InputDecoration(
                  labelText: 'Gender',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Select Gender')),
                  ..._genderCodes.map((gender) {
                    return DropdownMenuItem<String>(
                      value: gender['Value1'],
                      child: Text(gender['Value1'] ?? ''),
                    );
                  }).toList(),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedGender = value);
                  }
                },
                validator: (value) => value?.isEmpty ?? true ? 'Gender is required' : null,
              ),
              const SizedBox(height: 16),
              _buildTextField(_userIdController, 'User ID'),
              const SizedBox(height: 16),
              _buildTextField(_roleController, 'Role'),
              const SizedBox(height: 16),
              _buildDateField('Date of Birth', _selectedDateOfBirth,
                      (date) => setState(() => _selectedDateOfBirth = date)),
              const SizedBox(height: 16),
              _buildDateField('Date of Joining', _selectedJoiningDate,
                      (date) => setState(() => _selectedJoiningDate = date)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _updateProfile,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator()
                        : const Text('Update Profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label,
      {TextInputType keyboardType = TextInputType.text,
        int maxLines = 1,
        bool obscureText = false,
        bool readOnly = false,
        Widget? suffixIcon}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: suffixIcon,
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      obscureText: obscureText,
      readOnly: readOnly,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter $label';
        }
        return null;
      },
    );
  }

  Widget _buildDateField(
      String label, DateTime? date, ValueChanged<DateTime> onDateSelected) {
    return TextFormField(
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.calendar_today),
      ),
      controller: TextEditingController(
        text: date != null ? DateFormat('MMMM d, yyyy').format(date) : '',
      ),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1900),
          lastDate: DateTime.now().add(const Duration(days: 3650)),
        );
        if (picked != null) {
          onDateSelected(picked);
        }
      },
      validator: (value) {
        if (date == null) {
          return 'Please select $label';
        }
        return null;
      },
    );
  }
}