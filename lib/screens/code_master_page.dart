import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_drawer.dart';
import 'package:intl/intl.dart';

class CodeMasterPage extends StatefulWidget {
  final String email;
  final String? role;
  const CodeMasterPage({super.key, required this.email, this.role});

  @override
  State<CodeMasterPage> createState() => _CodeMasterPageState();
}

class _CodeMasterPageState extends State<CodeMasterPage> {
  String _search = '';
  final bool _showActive = true;
  List<Map<String, dynamic>> _codes = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  String _selectedType = 'leave type';
  final List<String> _types = ['leave type', 'designation', 'gender', 'department', 'company location'];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    if (widget.role != null) {
      setState(() => _isAdmin = widget.role!.toLowerCase() == 'admin');
      if (_isAdmin) _fetchCodes();
    } else {
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();
      if (userSnap.docs.isNotEmpty) {
        final role =
        userSnap.docs.first.data()['role']?.toString().toLowerCase();
        setState(() => _isAdmin = role == 'admin');
        if (_isAdmin) _fetchCodes();
      }
    }
  }

  Future<void> _fetchCodes() async {
    setState(() => _isLoading = true);
    final query = FirebaseFirestore.instance.collection('codes_master');
    final snapshot = await query.get();
    setState(() {
      _codes = snapshot.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredCodes {
    return _codes.where((code) {
      final matchesType = code['type'] == _selectedType;
      final matchesActive = _showActive ? code['Active'] == true : true;
      final matchesSearch = _search.isEmpty ||
          (code['Long Description'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_search.toLowerCase()) ||
          (code['Short Description'] ?? '')
              .toString()
              .toLowerCase()
              .contains(_search.toLowerCase());
      return matchesType && matchesActive && matchesSearch;
    }).toList();
  }

  void _showEditDialog([Map<String, dynamic>? code]) {
    final isEditing = code != null;
    final TextEditingController longDescController =
    TextEditingController(text: code?['Long Description'] ?? '');
    final TextEditingController shortDescController =
    TextEditingController(text: code?['Short Description'] ?? '');
    final TextEditingController value1Controller =
    TextEditingController(text: code?['Value1'] ?? '');

    // Company location specific controllers
    final TextEditingController addressController =
    TextEditingController(text: code?['address'] ?? '');
    final TextEditingController latitudeController =
    TextEditingController(text: code?['latitude']?.toString() ?? '');
    final TextEditingController longitudeController =
    TextEditingController(text: code?['longitude']?.toString() ?? '');
    final TextEditingController distanceController =
    TextEditingController(text: code?['allowed_distance']?.toString() ?? '100');
    final TextEditingController securityKeyController =
    TextEditingController(text: code?['security_key'] ?? '');

    bool active = code?['Active'] ?? true;
    String type = code?['type'] ?? _selectedType;

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEditing ? 'Edit ${type.toUpperCase()}' : 'Add ${type.toUpperCase()}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                  ),
                  items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => type = val);
                  },
                ),
                const SizedBox(height: 16),

                // Company Location specific fields
                if (type == 'company location') ...[
                  TextField(
                    controller: value1Controller,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Location Name',
                      labelStyle: TextStyle(color: colorScheme.onSurface),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.location_on, color: colorScheme.onSurface),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Full Address',
                      labelStyle: TextStyle(color: colorScheme.onSurface),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.home, color: colorScheme.onSurface),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: latitudeController,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Latitude',
                            labelStyle: TextStyle(color: colorScheme.onSurface),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.gps_fixed, color: colorScheme.onSurface),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: longitudeController,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            labelText: 'Longitude',
                            labelStyle: TextStyle(color: colorScheme.onSurface),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.gps_fixed, color: colorScheme.onSurface),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: distanceController,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Allowed Distance (meters)',
                      labelStyle: TextStyle(color: colorScheme.onSurface),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      prefixIcon: Icon(Icons.radar, color: colorScheme.onSurface),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest,
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: securityKeyController,
                    decoration: const InputDecoration(
                      labelText: 'Security Key (25 HEX)',
                      border: OutlineInputBorder(),
                      hintText: 'e.g. 1A2B3C4D5E6F7A8B9C0D1E2F3',
                    ),
                    maxLength: 25,
                  ),
                ] else ...[
                  // Existing fields for other types
                  if (type == 'designation' || type == 'gender' || type == 'department')
                    TextField(
                      controller: value1Controller,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: type == 'designation' ? 'Designation Name' :
                        type == 'gender' ? 'Gender Name' : 'Department Name',
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(Icons.category, color: colorScheme.onSurface),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  if (type == 'leave type')
                    TextField(
                      controller: value1Controller,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(Icons.category, color: colorScheme.onSurface),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (type == 'leave type') ...[
                    TextField(
                      controller: longDescController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Long Description',
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(Icons.description, color: colorScheme.onSurface),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: shortDescController,
                      style: TextStyle(color: colorScheme.onSurface),
                      decoration: InputDecoration(
                        labelText: 'Short Description',
                        labelStyle: TextStyle(color: colorScheme.onSurface),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: Icon(Icons.short_text, color: colorScheme.onSurface),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],
                SwitchListTile(
                  value: active,
                  onChanged: (val) => setState(() => active = val),
                  title: Text(
                    'Active',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  activeColor: colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  final data = {
                    'type': type,
                    'Active': active,
                    'created_by': widget.email,
                    'created_at': FieldValue.serverTimestamp(),
                    'updated_by': widget.email,
                    'updated_at': FieldValue.serverTimestamp(),
                  };

                  // Add type-specific data
                  if (type == 'company location') {
                    data['Value1'] = value1Controller.text;
                    data['address'] = addressController.text;
                    data['latitude'] = double.tryParse(latitudeController.text) ?? 0.0;
                    data['longitude'] = double.tryParse(longitudeController.text) ?? 0.0;
                    data['allowed_distance'] = double.tryParse(distanceController.text) ?? 100.0;
                    data['security_key'] = securityKeyController.text;
                  } else if (type == 'leave type') {
                    data['Value1'] = value1Controller.text;
                    data['Long Description'] = longDescController.text;
                    data['Short Description'] = shortDescController.text;
                  } else {
                    data['Value1'] = value1Controller.text;
                  }

                  if (isEditing) {
                    await FirebaseFirestore.instance
                        .collection('codes_master')
                        .doc(code['id'])
                        .update(data);
                  } else {
                    await FirebaseFirestore.instance
                        .collection('codes_master')
                        .add(data);
                  }

                  Navigator.pop(context);
                  _fetchCodes();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${type.toUpperCase()} ${isEditing ? 'updated' : 'added'} successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
              child: Text(isEditing ? 'Update' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  void _deleteCode(String id) async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete Code',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to delete this code?',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('codes_master')
          .doc(id)
          .delete();
      _fetchCodes();
    }
  }

  Future<void> _initializeSampleData() async {
    final colorScheme = Theme.of(context).colorScheme;

    // Check if data already exists
    final hasData = await _hasCodeMasterData();
    if (hasData) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Sample Data Exists',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          content: Text(
            'Sample data already exists. Do you want to add it again?',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.primary),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Initializing sample data...',
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );

    try {
      await _addSampleData();
      Navigator.pop(context); // Close loading dialog

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample data initialized successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh the codes list
      _fetchCodes();
    } catch (e) {
      Navigator.pop(context); // Close loading dialog

      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error initializing sample data: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _hasCodeMasterData() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('codes_master').limit(1).get();
      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking code master data: $e');
      return false;
    }
  }

  Future<void> _addSampleData() async {
    final firestore = FirebaseFirestore.instance;

    // Sample designations
    final designations = [
      {'type': 'designation', 'Value1': 'Software Developer', 'Long Description': 'Develops software applications and systems'},
      {'type': 'designation', 'Value1': 'Senior Software Developer', 'Long Description': 'Experienced software developer with leadership responsibilities'},
      {'type': 'designation', 'Value1': 'Junior Software Developer', 'Long Description': 'Entry-level software developer'},
      {'type': 'designation', 'Value1': 'QA Engineer', 'Long Description': 'Quality Assurance Engineer responsible for testing'},
      {'type': 'designation', 'Value1': 'Flutter Developer', 'Long Description': 'Specialized in Flutter mobile app development'},
      {'type': 'designation', 'Value1': 'Project Manager', 'Long Description': 'Manages project timelines and team coordination'},
      {'type': 'designation', 'Value1': 'UI/UX Designer', 'Long Description': 'Designs user interfaces and user experiences'},
      {'type': 'designation', 'Value1': 'DevOps Engineer', 'Long Description': 'Manages deployment and infrastructure'},
    ];

    // Sample departments
    final departments = [
      {'type': 'department', 'Value1': 'Engineering', 'Long Description': 'Software development and engineering team'},
      {'type': 'department', 'Value1': 'Quality Assurance', 'Long Description': 'Testing and quality assurance team'},
      {'type': 'department', 'Value1': 'Design', 'Long Description': 'UI/UX design and creative team'},
      {'type': 'department', 'Value1': 'Project Management', 'Long Description': 'Project coordination and management team'},
      {'type': 'department', 'Value1': 'DevOps', 'Long Description': 'Infrastructure and deployment team'},
      {'type': 'department', 'Value1': 'Mobile Development', 'Long Description': 'Mobile app development team'},
      {'type': 'department', 'Value1': 'Web Development', 'Long Description': 'Web application development team'},
      {'type': 'department', 'Value1': 'Human Resources', 'Long Description': 'HR and recruitment team'},
    ];

    // Sample genders
    final genders = [
      {'type': 'gender', 'Value1': 'Male', 'Long Description': 'Male gender'},
      {'type': 'gender', 'Value1': 'Female', 'Long Description': 'Female gender'},
      {'type': 'gender', 'Value1': 'Other', 'Long Description': 'Other gender options'},
      {'type': 'gender', 'Value1': 'Prefer not to say', 'Long Description': 'Prefer not to disclose gender'},
    ];

    // Sample leave types
    final leaveTypes = [
      {'type': 'leave type', 'Value1': 'Annual Leave', 'Long Description': 'Regular annual vacation leave', 'Short Description': 'AL'},
      {'type': 'leave type', 'Value1': 'Sick Leave', 'Long Description': 'Medical and health-related leave', 'Short Description': 'SL'},
      {'type': 'leave type', 'Value1': 'Personal Leave', 'Long Description': 'Personal and family-related leave', 'Short Description': 'PL'},
      {'type': 'leave type', 'Value1': 'Maternity Leave', 'Long Description': 'Maternity and pregnancy-related leave', 'Short Description': 'ML'},
      {'type': 'leave type', 'Value1': 'Paternity Leave', 'Long Description': 'Paternity and father-related leave', 'Short Description': 'PL'},
      {'type': 'leave type', 'Value1': 'Bereavement Leave', 'Long Description': 'Leave for bereavement and funeral', 'Short Description': 'BL'},
    ];

    // Add all sample data
    final allData = [...designations, ...departments, ...genders, ...leaveTypes];

    for (var data in allData) {
      try {
        await firestore.collection('codes_master').add({
          ...data,
          'Active': true,
          'createdBy': widget.email,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        print('Error adding ${data['Value1']}: $e');
      }
    }

    // Add a few sample security keys in the code master for demo/testing
    final sampleKeys = [
      '1A2B3C4D5E6F7A8B9C0D1E2F3',
      'ABCDEF1234567890ABCDE1234',
      'FEDCBA9876543210FEDCBA987',
    ];
    for (final key in sampleKeys) {
      await FirebaseFirestore.instance.collection('codes_master').add({
        'type': 'attendance_security_key',
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'Value1': 'Main Office',
        'latitude': 0.0,
        'longitude': 0.0,
        'key': key,
        'created_at': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: const Text('Code Master'),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
        ),
        drawer: DashboardDrawer(
          onThemeChanged: () {
            setState(() {});
          },
          userEmail: widget.email,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Access Denied',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This page is only accessible to administrators.',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Master'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onPrimary),
            onPressed: _fetchCodes,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: Icon(Icons.add, color: colorScheme.onPrimary),
            onPressed: () => _showEditDialog(),
            tooltip: 'Add Code',
          ),
          IconButton(
            icon: Icon(Icons.data_usage, color: colorScheme.onPrimary),
            onPressed: _initializeSampleData,
            tooltip: 'Initialize Sample Data',
          ),
        ],
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
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      value: _selectedType,
                      decoration: const InputDecoration(
                        labelText: 'Filter by Type',
                        border: OutlineInputBorder(),
                      ),
                      items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedType = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 250,
                    child: TextField(
                      decoration: const InputDecoration(
                          hintText: 'Search...'
                      ),
                      onChanged: (val) => setState(() => _search = val),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _filteredCodes.isEmpty
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
                    'No codes found',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _search.isEmpty
                        ? 'Try adding a new code'
                        : 'Try adjusting your search',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _filteredCodes.length,
              itemBuilder: (context, index) {
                final code = _filteredCodes[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            code['Value1'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: (code['Active'] == true)
                                ? Colors.green.withOpacity(0.1)
                                : Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            (code['Active'] == true)
                                ? 'Active'
                                : 'Inactive',
                            style: TextStyle(
                              color: (code['Active'] == true)
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),
                        if (code['type'] == 'leave type') ...[
                          Text(
                            code['Long Description'] ?? '',
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                          if (code['Short Description'] != null && code['Short Description'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Short: ${code['Short Description']}',
                              style: TextStyle(
                                color: colorScheme.onSurface.withOpacity(0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.edit,
                            color: colorScheme.primary,
                          ),
                          onPressed: () => _showEditDialog(code),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete,
                            color: colorScheme.error,
                          ),
                          onPressed: () => _deleteCode(code['id']),
                          tooltip: 'Delete',
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
        onPressed: () => _showEditDialog(),
        tooltip: 'Add Code',
        backgroundColor: colorScheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}