import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../widgets/dashboard_drawer.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'dart:async';


class AttendancePage extends StatefulWidget {
  final String email;
  final bool isAdmin;
  const AttendancePage({super.key, required this.email, required this.isAdmin});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> with TickerProviderStateMixin {
  bool _isLoading = true;
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _attendanceRecords = [];
  final Map<String, int?> _attendanceStatus = {}; // email -> 0:Present, 1:Absent, 2:Leave
  final Map<String, String> _notes = {};
  String _searchQuery = '';
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;
  final Set<String> _selectedEmails = {};

  // Employee attendance state
  bool _isCheckingIn = false;
  bool _isCheckingOut = false;
  DateTime? _lastCheckInTime;
  DateTime? _lastCheckOutTime;
  String _currentStatus = 'Not Checked In';
  DateTime _currentTime = DateTime.now();

  // QR Code attendance state
  bool _isGeneratingQR = false;
  bool _isScanning = false;
  String? _qrData;
  String? _officeLocation;
  double? _officeLatitude;
  double? _officeLongitude;
  double _allowedDistance = 100.0; // meters
  MobileScannerController? _scannerController;

  // Employee location state
  Position? _currentEmployeeLocation;
  String _employeeLocationAddress = 'Location not fetched yet.';
  double _distanceFromOffice = 0.0;
  bool _isLocationValid = false;

  // Admin company location state
  List<Map<String, dynamic>> _companyLocations = [];
  Map<String, dynamic>? _selectedCompanyLocation;

  // Bottom navigation state
  int _currentIndex = 0;
  late TabController _tabController;

  Timer? _timeUpdateTimer;

  String? _selectedSecurityKey;
  List<String> _availableSecurityKeys = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadOfficeLocation();
    _loadCurrentAttendanceStatus();
    _startTimeUpdate();
    if (widget.isAdmin) {
      _fetchEmployeesAndAttendance();
      _fetchCompanyLocations();
      _fetchSecurityKeys();
    } else {
      _fetchAndValidateEmployeeLocation();
    }
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    _tabController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _startTimeUpdate() {
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  Future<void> _fetchEmployeesAndAttendance() async {
    setState(() => _isLoading = true);
    try {
      // Fetch all employees
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      _employees = usersSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).where((user) => (user['role'] ?? '').toLowerCase() != 'admin').toList();

      // Fetch attendance for the selected date
      final dateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final attendanceSnapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isEqualTo: Timestamp.fromDate(dateOnly))
          .get();

      _attendanceRecords = attendanceSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Pre-fill attendance status
      for (var emp in _employees) {
        final email = emp['email'];
        final attendanceRecord = _attendanceRecords.firstWhere(
              (record) => record['email'] == email,
          orElse: () => {},
        );

        if (attendanceRecord.isNotEmpty) {
          final status = attendanceRecord['status'] ?? 'present';
          _attendanceStatus[email] = status == 'present' ? 0 : status == 'absent' ? 1 : 2;
        } else {
          _attendanceStatus[email] = null;
        }
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _markAll(int status) {
    setState(() {
      for (var emp in _filteredEmployees) {
        _attendanceStatus[emp['email']] = status;
      }
    });
  }

  void _showNoteDialog(String email) async {
    final controller = TextEditingController(text: _notes[email] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remark'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Enter remark...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null) {
      setState(() => _notes[email] = result);
    }
  }

  Future<void> _saveAttendance() async {
    if (_attendanceStatus.values.any((v) => v == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please mark attendance for all employees.'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final dateOnly = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);

      for (var emp in _employees) {
        final email = emp['email'];
        final statusIdx = _attendanceStatus[email];
        String status = statusIdx == 0 ? 'present' : statusIdx == 1 ? 'absent' : 'leave';

        // Check if attendance already exists for this user/date
        final existing = await FirebaseFirestore.instance
            .collection('attendance')
            .where('email', isEqualTo: email)
            .where('date', isEqualTo: Timestamp.fromDate(dateOnly))
            .get();

        if (existing.docs.isNotEmpty) {
          // Update existing record
          await FirebaseFirestore.instance.collection('attendance').doc(existing.docs.first.id).update({
            'status': status,
            'markedby': widget.email,
            'remark': _notes[email] ?? '',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          // Add new record
          await FirebaseFirestore.instance.collection('attendance').add({
            'email': email,
            'date': Timestamp.fromDate(dateOnly),
            'status': status,
            'markedby': widget.email,
            'remark': _notes[email] ?? '',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance saved!'), backgroundColor: Colors.green),
      );
      _fetchEmployeesAndAttendance();
    } catch (e) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _editAttendanceDialog(Map<String, dynamic> record) async {
    int? statusIdx = record['status'] == 'present'
        ? 0
        : record['status'] == 'absent'
        ? 1
        : record['status'] == 'leave'
        ? 2
        : null;

    DateTime baseDate = record['date'] is Timestamp ? (record['date'] as Timestamp).toDate() : DateTime.now();
    DateTime checkIn = record['checkInTime'] is Timestamp ? (record['checkInTime'] as Timestamp).toDate() : baseDate;
    DateTime checkOut = record['checkOutTime'] is Timestamp ? (record['checkOutTime'] as Timestamp).toDate() : baseDate;

    final statusOptions = ['Present', 'Absent', 'Leave'];
    final formKey = GlobalKey<FormState>();
    String? validationError;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Attendance'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: statusIdx,
                  items: List.generate(3, (i) => DropdownMenuItem(value: i, child: Text(statusOptions[i]))),
                  onChanged: (val) => setDialogState(() => statusIdx = val),
                  decoration: const InputDecoration(labelText: 'Status'),
                  validator: (value) {
                    if (value == null) return 'Please select a status';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                ListTile(
                  title: Text('Check In: ${_formatTimeForDisplay(checkIn)}'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(checkIn),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        checkIn = DateTime(baseDate.year, baseDate.month, baseDate.day, picked.hour, picked.minute);
                        // Validate check-out time
                        if (checkOut.isBefore(checkIn)) {
                          checkOut = checkIn.add(const Duration(hours: 8)); // Default 8-hour workday
                        }
                        validationError = null;
                      });
                    }
                  },
                ),
                ListTile(
                  title: Text('Check Out: ${_formatTimeForDisplay(checkOut)}'),
                  trailing: const Icon(Icons.access_time),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(checkOut),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        checkOut = DateTime(baseDate.year, baseDate.month, baseDate.day, picked.hour, picked.minute);
                        // Validate check-out time
                        if (checkOut.isBefore(checkIn)) {
                          validationError = 'Check-out time must be after check-in time';
                        } else {
                          validationError = null;
                        }
                      });
                    }
                  },
                ),
                if (validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      validationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Work Duration: ${_calculateWorkDuration(checkIn, checkOut)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: validationError != null ? null : () async {
                if (!formKey.currentState!.validate()) return;

                if (checkOut.isBefore(checkIn)) {
                  setDialogState(() {
                    validationError = 'Check-out time must be after check-in time';
                  });
                  return;
                }

                try {
                  await FirebaseFirestore.instance.collection('attendance').doc(record['id']).update({
                    'status': statusIdx == 0 ? 'present' : statusIdx == 1 ? 'absent' : 'leave',
                    'checkInTime': Timestamp.fromDate(checkIn),
                    'checkOutTime': Timestamp.fromDate(checkOut),
                    'updatedBy': widget.email,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                  _fetchEmployeesAndAttendance();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Attendance updated successfully!'), backgroundColor: Colors.green),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error updating attendance: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeForDisplay(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _calculateWorkDuration(DateTime checkIn, DateTime checkOut) {
    if (checkOut.isBefore(checkIn)) return 'Invalid';
    final duration = checkOut.difference(checkIn);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  List<Map<String, dynamic>> get _filteredEmployees {
    return _employees.where((emp) {
      final name = '${emp['firstName'] ?? ''} ${emp['lastName'] ?? ''}'.toLowerCase();
      final email = (emp['email'] ?? '').toLowerCase();
      final matchesSearch = _searchQuery.isEmpty || name.contains(_searchQuery.toLowerCase()) || email.contains(_searchQuery.toLowerCase());
      return matchesSearch;
    }).toList();
  }

  // Load current attendance status for employee
  Future<void> _loadCurrentAttendanceStatus() async {
    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);

      final attendanceDoc = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();

      if (attendanceDoc.exists) {
        final data = attendanceDoc.data()!;
        if (data['checkInTime'] != null) {
          setState(() {
            _lastCheckInTime = (data['checkInTime'] as Timestamp).toDate();
            if (data['checkOutTime'] != null) {
              _lastCheckOutTime = (data['checkOutTime'] as Timestamp).toDate();
              _currentStatus = 'Checked Out';
            } else {
              _currentStatus = 'Checked In';
            }
          });
        }
      }
    } catch (e) {
      print('Error loading attendance status: $e');
    }
  }

  String _formatDateTimeField(dynamic value) {
    if (value == null) return '--:--';
    if (value is Timestamp) {
      final dt = value.toDate();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (value is DateTime) {
      final dt = value;
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Attendance Management'),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: 'View Previous Attendance',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => Dialog(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _AdminAttendanceCalendar(
                        onDateSelected: (selectedDate) async {
                          Navigator.pop(context); // Close calendar
                          // Fetch all attendance records for the selected date
                          final dateOnly = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
                          final snapshot = await FirebaseFirestore.instance
                              .collection('attendance')
                              .where('date', isEqualTo: Timestamp.fromDate(dateOnly))
                              .get();
                          final records = snapshot.docs.map((doc) => doc.data()).toList();
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(DateFormat('EEEE, MMMM dd, yyyy').format(selectedDate)),
                              content: records.isEmpty
                                  ? const Text('No attendance records for this date.')
                                  : SizedBox(
                                width: 350,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: records.length,
                                  itemBuilder: (context, index) {
                                    final record = records[index];
                                    return ListTile(
                                      title: Text(record['name'] ?? record['email'] ?? ''),
                                      subtitle: Text('Status: ${(record['status'] ?? '').toString().toUpperCase()}'),
                                    );
                                  },
                                ),
                              ),
                              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
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
            ? const Center(child: CircularProgressIndicator())
            : _buildAdminAttendanceBody(),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AttendanceHistoryExportScreen(),
              ),
            );
          },
          tooltip: 'Print/Export Attendance History',
          child: const Icon(Icons.print),
        ),
      );
    } else {
      // Employee view
      return Scaffold(
        appBar: AppBar(
          title: const Text('Attendance'),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (!widget.isAdmin)
              IconButton(
                icon: const Icon(Icons.calendar_month),
                tooltip: 'View Previous Attendance',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: _EmployeeAttendanceCalendar(
                          email: widget.email,
                          onDateSelected: (selectedDate, attendanceData) {
                            Navigator.pop(context); // Close calendar
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text(DateFormat('EEEE, MMMM dd, yyyy').format(selectedDate)),
                                content: attendanceData == null
                                    ? const Text('No attendance record for this date.')
                                    : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Status: ${attendanceData['status']?.toString().toUpperCase() ?? 'Unknown'}'),
                                    Text('Check In: ${_formatDateTimeField(attendanceData['checkInTime'])}'),
                                    Text('Check Out: ${_formatDateTimeField(attendanceData['checkOutTime'])}'),
                                    if (attendanceData['remark'] != null && attendanceData['remark'].toString().isNotEmpty)
                                      Text('Remark: ${attendanceData['remark']}'),
                                  ],
                                ),
                                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
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
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildEmployeeAttendanceBody(),
        ),
      );
    }
  }

  Widget _buildEmployeeAttendanceBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;

    return Scaffold(
      body: TabBarView(
        controller: _tabController,
        children: [
          // Main Attendance Tab
          _buildMainAttendanceTab(block, fontScale, colorScheme),
          // Attendance History Tab
          _buildAttendanceHistoryTab(block, fontScale, colorScheme),
          // Today Summary Tab
          _buildTodaySummaryTab(block, fontScale, colorScheme),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: TabBar(
            controller: _tabController,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            indicatorColor: colorScheme.primary,
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
            tabs: [
              Tab(
                icon: Icon(Icons.home, size: block * 5),
                text: 'Attendance',
              ),
              Tab(
                icon: Icon(Icons.history, size: block * 5),
                text: 'History',
              ),
              Tab(
                icon: Icon(Icons.summarize, size: block * 5),
                text: 'Summary',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainAttendanceTab(double block, double fontScale, ColorScheme colorScheme) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Current Status Card
          Card(
            margin: EdgeInsets.symmetric(horizontal: block * 4, vertical: block * 2),
            elevation: 4,
            child: Container(
              padding: EdgeInsets.all(block * 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    colorScheme.primaryContainer,
                    colorScheme.primaryContainer.withOpacity(0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(block * 2),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Status',
                              style: TextStyle(
                                fontSize: 14 * fontScale,
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: block * 1),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: block * 3, vertical: block * 1),
                              decoration: BoxDecoration(
                                color: _getStatusColor(_currentStatus),
                                borderRadius: BorderRadius.circular(block * 3),
                              ),
                              child: Text(
                                _currentStatus,
                                style: TextStyle(
                                  fontSize: 16 * fontScale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: EdgeInsets.all(block * 2),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _getStatusIcon(_currentStatus),
                          color: Colors.white,
                          size: block * 6,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: block * 3),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: block * 4, color: colorScheme.onPrimaryContainer),
                      SizedBox(width: block * 2),
                      Text(
                        'Current Time: ${_formatTimeForDisplay(_currentTime)}',
                        style: TextStyle(
                          fontSize: 16 * fontScale,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Check-in/Check-out Times Card
          if (_lastCheckInTime != null || _lastCheckOutTime != null)
            Card(
              margin: EdgeInsets.symmetric(horizontal: block * 4, vertical: block * 2),
              elevation: 2,
              child: Padding(
                padding: EdgeInsets.all(block * 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Today\'s Attendance',
                      style: TextStyle(
                        fontSize: 16 * fontScale,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: block * 3),
                    if (_lastCheckInTime != null) ...[
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(block * 1.5),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(block * 2),
                            ),
                            child: Icon(Icons.login, color: Colors.green, size: block * 4),
                          ),
                          SizedBox(width: block * 3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-in Time',
                                  style: TextStyle(
                                    fontSize: 12 * fontScale,
                                    color: colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                Text(
                                  _formatTimeForDisplay(_lastCheckInTime!),
                                  style: TextStyle(
                                    fontSize: 16 * fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: block * 2),
                    ],
                    if (_lastCheckOutTime != null) ...[
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(block * 1.5),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(block * 2),
                            ),
                            child: Icon(Icons.logout, color: Colors.red, size: block * 4),
                          ),
                          SizedBox(width: block * 3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Check-out Time',
                                  style: TextStyle(
                                    fontSize: 12 * fontScale,
                                    color: colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                                Text(
                                  _formatTimeForDisplay(_lastCheckOutTime!),
                                  style: TextStyle(
                                    fontSize: 16 * fontScale,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),

          // Location Status Card
          Card(
            margin: EdgeInsets.symmetric(horizontal: block * 4, vertical: block * 2),
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.all(block * 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isLocationValid ? Icons.location_on : Icons.location_off,
                        color: _isLocationValid ? Colors.green : Colors.red,
                        size: block * 5,
                      ),
                      SizedBox(width: block * 2),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location Status',
                              style: TextStyle(
                                fontSize: 16 * fontScale,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              _isLocationValid ? 'Within office range' : 'Outside office range',
                              style: TextStyle(
                                fontSize: 12 * fontScale,
                                color: _isLocationValid ? Colors.green : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: block * 2),
                  Text(
                    _employeeLocationAddress,
                    style: TextStyle(
                      fontSize: 12 * fontScale,
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  if (_distanceFromOffice > 0) ...[
                    SizedBox(height: block * 1),
                    Text(
                      'Distance from office: ${_distanceFromOffice.toStringAsFixed(1)} meters',
                      style: TextStyle(
                        fontSize: 12 * fontScale,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Action Buttons
          Padding(
            padding: EdgeInsets.all(block * 4),
            child: Column(
              children: [
                // Check-in Button
                if (_currentStatus == 'Not Checked In' || _currentStatus == 'Checked Out')
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: block * 3),
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingIn ? null : _handleCheckInWithQR,
                      icon: _isCheckingIn
                          ? SizedBox(
                        width: block * 4,
                        height: block * 4,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Icon(Icons.qr_code_scanner, size: block * 5),
                      label: Text(
                        _isCheckingIn ? 'Processing Check-in...' : 'Check In with QR',
                        style: TextStyle(
                          fontSize: 16 * fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: block * 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(block * 2),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),

                // Check-out Button
                if (_currentStatus == 'Checked In')
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: block * 3),
                    child: ElevatedButton.icon(
                      onPressed: _isCheckingOut ? null : _handleCheckOutWithQR,
                      icon: _isCheckingOut
                          ? SizedBox(
                        width: block * 4,
                        height: block * 4,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Icon(Icons.qr_code_scanner, size: block * 5),
                      label: Text(
                        _isCheckingOut ? 'Processing Check-out...' : 'Check Out with QR',
                        style: TextStyle(
                          fontSize: 16 * fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: block * 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(block * 2),
                        ),
                        elevation: 4,
                      ),
                    ),
                  ),

                // Manual Check-in/Check-out (Alternative)
                if (_currentStatus == 'Not Checked In' || _currentStatus == 'Checked Out')
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: block * 3),
                    child: OutlinedButton.icon(
                      onPressed: _isCheckingIn ? null : _handleManualCheckIn,
                      icon: Icon(Icons.touch_app, size: block * 4),
                      label: Text(
                        'Manual Check In',
                        style: TextStyle(
                          fontSize: 14 * fontScale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        padding: EdgeInsets.symmetric(vertical: block * 3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(block * 2),
                        ),
                      ),
                    ),
                  ),

                if (_currentStatus == 'Checked In')
                  Container(
                    width: double.infinity,
                    margin: EdgeInsets.only(bottom: block * 3),
                    child: OutlinedButton.icon(
                      onPressed: _isCheckingOut ? null : _handleManualCheckOut,
                      icon: Icon(Icons.touch_app, size: block * 4),
                      label: Text(
                        'Manual Check Out',
                        style: TextStyle(
                          fontSize: 14 * fontScale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: EdgeInsets.symmetric(vertical: block * 3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(block * 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHistoryTab(double block, double fontScale, ColorScheme colorScheme) {
    return _EmployeeAttendanceHistoryView(email: widget.email);
  }

  Widget _buildTodaySummaryTab(double block, double fontScale, ColorScheme colorScheme) {
    final now = DateTime.now();

    return SingleChildScrollView(
      padding: EdgeInsets.all(block * 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: EdgeInsets.all(block * 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Today\'s Summary',
                    style: TextStyle(
                      fontSize: 20 * fontScale,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: block * 3),
                  _buildSummaryRow('Date', DateFormat('EEEE, MMMM dd, yyyy').format(now), Icons.calendar_today, block, fontScale, colorScheme),
                  _buildSummaryRow('Current Status', _currentStatus, _getStatusIcon(_currentStatus), block, fontScale, colorScheme),
                  if (_lastCheckInTime != null)
                    _buildSummaryRow('Check-in Time', _formatTimeForDisplay(_lastCheckInTime!), Icons.login, block, fontScale, colorScheme),
                  if (_lastCheckOutTime != null)
                    _buildSummaryRow('Check-out Time', _formatTimeForDisplay(_lastCheckOutTime!), Icons.logout, block, fontScale, colorScheme),
                  if (_lastCheckInTime != null && _lastCheckOutTime != null)
                    _buildSummaryRow('Work Duration', _calculateWorkDuration(_lastCheckInTime!, _lastCheckOutTime!), Icons.access_time, block, fontScale, colorScheme),
                  _buildSummaryRow('Location Status', _isLocationValid ? 'Valid' : 'Invalid', _isLocationValid ? Icons.location_on : Icons.location_off, block, fontScale, colorScheme),
                  if (_distanceFromOffice > 0)
                    _buildSummaryRow('Distance from Office', '${_distanceFromOffice.toStringAsFixed(1)} meters', Icons.straighten, block, fontScale, colorScheme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon, double block, double fontScale, ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: block * 1.5),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(block * 1.5),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(block * 2),
            ),
            child: Icon(icon, color: colorScheme.primary, size: block * 4),
          ),
          SizedBox(width: block * 3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12 * fontScale,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16 * fontScale,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for UI
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Checked In':
        return Colors.green;
      case 'Checked Out':
        return Colors.red;
      case 'Late':
        return Colors.orange;
      case 'Half Day':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'Checked In':
        return Icons.check_circle;
      case 'Checked Out':
        return Icons.logout;
      case 'Late':
        return Icons.schedule;
      case 'Half Day':
        return Icons.access_time;
      default:
        return Icons.pending;
    }
  }

  // Manual check-in/check-out methods
  Future<void> _handleManualCheckIn() async {
    if (_isCheckingIn) return;

    setState(() => _isCheckingIn = true);

    try {
      await _performCheckInWithoutLocation();
    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showErrorDialog('Error during manual check-in: $e');
    }
  }

  Future<void> _handleManualCheckOut() async {
    if (_isCheckingOut) return;

    setState(() => _isCheckingOut = true);

    try {
      await _performCheckOutWithoutLocation();
    } catch (e) {
      setState(() => _isCheckingOut = false);
      _showErrorDialog('Error during manual check-out: $e');
    }
  }

  // Quick action methods
  void _showAttendanceHistory() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: _EmployeeAttendanceCalendar(
            email: widget.email,
            onDateSelected: (selectedDate, attendanceData) {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(DateFormat('EEEE, MMMM dd, yyyy').format(selectedDate)),
                  content: attendanceData == null
                      ? const Text('No attendance record for this date.')
                      : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${attendanceData['status']?.toString().toUpperCase() ?? 'Unknown'}'),
                      Text('Check In: ${_formatDateTimeField(attendanceData['checkInTime'])}'),
                      Text('Check Out: ${_formatDateTimeField(attendanceData['checkOutTime'])}'),
                      if (attendanceData['remark'] != null && attendanceData['remark'].toString().isNotEmpty)
                        Text('Remark: ${attendanceData['remark']}'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showTodaySummary() {
    final now = DateTime.now();
    final dateId = DateFormat('yyyy-MM-dd').format(now);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Today\'s Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${DateFormat('EEEE, MMMM dd, yyyy').format(now)}'),
            Text('Current Status: $_currentStatus'),
            if (_lastCheckInTime != null)
              Text('Check-in: ${_formatTimeForDisplay(_lastCheckInTime!)}'),
            if (_lastCheckOutTime != null)
              Text('Check-out: ${_formatTimeForDisplay(_lastCheckOutTime!)}'),
            if (_lastCheckInTime != null && _lastCheckOutTime != null)
              Text('Work Duration: ${_calculateWorkDuration(_lastCheckInTime!, _lastCheckOutTime!)}'),
          ],
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

  // New methods for QR-based check-in/check-out
  Future<void> _handleCheckInWithQR() async {
    if (_isCheckingIn) return;

    setState(() => _isCheckingIn = true);

    try {
      await _startScanningForCheckIn();
    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showErrorDialog('Error starting QR scanner: $e');
    }
  }

  Future<void> _handleCheckOutWithQR() async {
    if (_isCheckingOut) return;

    setState(() => _isCheckingOut = true);

    try {
      await _startScanningForCheckOut();
    } catch (e) {
      setState(() => _isCheckingOut = false);
      _showErrorDialog('Error starting QR scanner: $e');
    }
  }

  Future<void> _startScanningForCheckIn() async {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

      setState(() => _isScanning = true);

      // Show QR scanner dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final media = MediaQuery.of(context);
          final fontScale = media.size.width < 400 ? 0.85 : media.size.width < 600 ? 0.95 : 1.0;
          return AlertDialog(
            title: Text('Scan QR Code to Check In', style: TextStyle(fontSize: 16 * fontScale)),
            content: SizedBox(
              height: 300,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          _processQRCodeForCheckIn(barcode.rawValue!);
                          break;
                        }
                      }
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: FloatingActionButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _isScanning = false;
                          _isCheckingIn = false;
                        });
                        _scannerController?.dispose();
                      },
                      backgroundColor: Colors.red,
                      mini: true,
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
        _isCheckingIn = false;
      });
      _showErrorDialog('Camera access error: $e');
    }
  }

  Future<void> _startScanningForCheckOut() async {
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );

      setState(() => _isScanning = true);

      // Show QR scanner dialog
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          final media = MediaQuery.of(context);
          final fontScale = media.size.width < 400 ? 0.85 : media.size.width < 600 ? 0.95 : 1.0;
          return AlertDialog(
            title: Text('Scan QR Code to Check Out', style: TextStyle(fontSize: 16 * fontScale)),
            content: SizedBox(
              height: 300,
              child: Stack(
                children: [
                  MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      for (final barcode in barcodes) {
                        if (barcode.rawValue != null) {
                          _processQRCodeForCheckOut(barcode.rawValue!);
                          break;
                        }
                      }
                    },
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: FloatingActionButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _isScanning = false;
                          _isCheckingOut = false;
                        });
                        _scannerController?.dispose();
                      },
                      backgroundColor: Colors.red,
                      mini: true,
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      setState(() {
        _isScanning = false;
        _isCheckingOut = false;
      });
      _showErrorDialog('Camera access error: $e');
    }
  }

  Future<void> _processQRCodeForCheckIn(String qrData) async {
    try {
      // Close scanner dialog
      Navigator.pop(context);
      setState(() => _isScanning = false);
      _scannerController?.dispose();

      // Validate QR code format
      Map<String, dynamic> qrMap;
      try {
        qrMap = jsonDecode(qrData) as Map<String, dynamic>;
      } catch (e) {
        _showErrorDialog('Invalid QR code format');
        setState(() => _isCheckingIn = false);
        return;
      }

      if (qrMap['type'] != 'attendance_checkin') {
        _showErrorDialog('Invalid QR code for attendance');
        setState(() => _isCheckingIn = false);
        return;
      }

      // --- SECURITY KEY VALIDATION ---
      final String? qrSecurityKey = qrMap['security_key'];
      if (qrSecurityKey == null || qrSecurityKey.length != 25) {
        _showErrorDialog('Invalid or missing security key in QR code.');
        setState(() => _isCheckingIn = false);
        return;
      }
      // Use already defined qrLocation and now
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final value1 = qrMap['location']?['Value1']?.toString() ?? 'unknown';
      final latitude = qrMap['location']?['latitude']?.toString() ?? '0.0';
      final longitude = qrMap['location']?['longitude']?.toString() ?? '0.0';
      final keyDocQuery = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'attendance_security_key')
          .where('date', isEqualTo: dateStr)
          .where('Value1', isEqualTo: value1)
          .where('latitude', isEqualTo: double.tryParse(latitude) ?? 0.0)
          .where('longitude', isEqualTo: double.tryParse(longitude) ?? 0.0)
          .limit(1)
          .get();
      String? expectedKey;
      if (keyDocQuery.docs.isNotEmpty) {
        expectedKey = keyDocQuery.docs.first.data()['key'] as String?;
      }
      if (expectedKey == null || expectedKey != qrSecurityKey) {
        _showErrorDialog('Security key mismatch. Please use a valid QR code.');
        setState(() => _isCheckingIn = false);
        return;
      }

      // --- LOCATION VALIDATION ---
      // Get office location from QR
      final qrLocation = qrMap['location'];
      if (qrLocation == null || qrLocation['latitude'] == null || qrLocation['longitude'] == null) {
        _showErrorDialog('QR code missing office location.');
        setState(() => _isCheckingIn = false);
        return;
      }
      final officeLat = (qrLocation['latitude'] as num).toDouble();
      final officeLng = (qrLocation['longitude'] as num).toDouble();
      final allowedDistance = _allowedDistance;

      // Get employee current location
      Position? position;
      String address = 'Unknown Location';
      try {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        _showErrorDialog('Could not fetch your location.');
        setState(() => _isCheckingIn = false);
        return;
      }

      // Calculate distance
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, officeLat, officeLng);
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);
      final docRef = FirebaseFirestore.instance.collection('attendance').doc('${widget.email}_$dateId');

      if (distance > allowedDistance) {
        // --- REJECTED CHECK-IN: Only show location warning, do not check or show security key error ---
        _showErrorDialog('You are not in the office location. Check-in rejected.');
        setState(() => _isCheckingIn = false);
        return;
      }

      // --- SECURITY KEY VALIDATION (only if location is valid) ---
      // Use the already defined qrSecurityKey, dateStr, value1, latitude, longitude, keyDocQuery, and expectedKey from above
      if (expectedKey == null || expectedKey != qrSecurityKey) {
        _showErrorDialog('Security key mismatch. Please use a valid QR code.');
        setState(() => _isCheckingIn = false);
        return;
      }

      // --- VALID CHECK-IN ---
      // Always save the security key in every attendance record
      await _performCheckInWithLocation(
        position,
        address,
        officeLat,
        officeLng,
        qrLocation['Long Description'] ?? '',
        distance,
        qrSecurityKey, // pass the security key
      );

    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showErrorDialog('Error processing QR code: $e');
    }
  }

  // New helper for valid check-in with location
  Future<void> _performCheckInWithLocation(Position position, String address, double officeLat, double officeLng, String officeAddress, double distance, String securityKey) async {
    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final lateThreshold = DateTime(now.year, now.month, now.day, 10, 15);
      final halfDayThreshold = DateTime(now.year, now.month, now.day, 12, 0);
      String status = 'present';
      String remark = 'QR check-in';
      bool isLate = false;
      bool isHalfDay = false;

      if (now.isAfter(halfDayThreshold)) {
        status = 'half-day';
        remark = 'QR check-in after 12:00 PM (Half Day)';
        isHalfDay = true;
      } else if (now.isAfter(lateThreshold)) {
        status = 'late';
        remark = 'QR check-in after 10:15 AM (Late)';
        isLate = true;
      }

      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);
      final docRef = FirebaseFirestore.instance.collection('attendance').doc('${widget.email}_$dateId');
      final existingAttendance = await docRef.get();

      final checkinLocation = {
        'latitude': position.latitude,
        'longitude': position.longitude,
        'address': address,
        'distance': distance,
        'accuracy': position.accuracy,
        'altitude': position.altitude,
        'speed': position.speed,
        'heading': position.heading,
      };
      final officeLocation = {
        'latitude': officeLat,
        'longitude': officeLng,
        'address': officeAddress,
      };

      if (existingAttendance.exists) {
        final existingRecord = existingAttendance.data()!;
        if (existingRecord['checkInTime'] != null) {
          _showErrorDialog('Already checked in today.');
          setState(() => _isCheckingIn = false);
          return;
        } else {
          await docRef.update({
            'checkInTime': Timestamp.fromDate(now),
            'status': status,
            'remark': remark,
            'checkin_location': checkinLocation,
            'office_location': officeLocation,
            'security_key': securityKey,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await docRef.set({
          'email': widget.email,
          'date': Timestamp.fromDate(dateOnly),
          'date_id': dateId,
          'checkInTime': Timestamp.fromDate(now),
          'status': status,
          'markedby': widget.email,
          'remark': remark,
          'checkin_location': checkinLocation,
          'office_location': officeLocation,
          'security_key': securityKey,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() {
        _lastCheckInTime = now;
        _currentStatus = isHalfDay ? 'Half Day' : isLate ? 'Late' : 'Checked In';
        _isCheckingIn = false;
      });

      _showSuccessDialog(
        isHalfDay
            ? 'Checked in after 12:00 PM (Half Day)!'
            : isLate
            ? 'Checked in after 10:15 AM (Late)!'
            : 'Successfully checked in at \\${DateFormat('HH:mm').format(now)}!',
        isHalfDay || isLate ? Colors.orange : Colors.green,
      );
    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showErrorDialog('Error checking in: $e');
    }
  }

  Future<void> _processQRCodeForCheckOut(String qrData) async {
    try {
      // Close scanner dialog
      Navigator.pop(context);
      setState(() => _isScanning = false);
      _scannerController?.dispose();

      // Validate QR code format
      Map<String, dynamic> qrMap;
      try {
        qrMap = jsonDecode(qrData) as Map<String, dynamic>;
      } catch (e) {
        _showErrorDialog('Invalid QR code format');
        setState(() => _isCheckingOut = false);
        return;
      }

      if (qrMap['type'] != 'attendance_checkin') {
        _showErrorDialog('Invalid QR code for attendance');
        setState(() => _isCheckingOut = false);
        return;
      }

      // --- SECURITY KEY VALIDATION ---
      final String? qrSecurityKey = qrMap['security_key'];
      if (qrSecurityKey == null || qrSecurityKey.length != 25) {
        _showErrorDialog('Invalid or missing security key in QR code.');
        setState(() => _isCheckingOut = false);
        return;
      }
      // Use already defined qrLocation and now
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final value1 = qrMap['location']?['Value1']?.toString() ?? 'unknown';
      final latitude = qrMap['location']?['latitude']?.toString() ?? '0.0';
      final longitude = qrMap['location']?['longitude']?.toString() ?? '0.0';
      final keyDocQuery = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'attendance_security_key')
          .where('date', isEqualTo: dateStr)
          .where('Value1', isEqualTo: value1)
          .where('latitude', isEqualTo: double.tryParse(latitude) ?? 0.0)
          .where('longitude', isEqualTo: double.tryParse(longitude) ?? 0.0)
          .limit(1)
          .get();
      String? expectedKey;
      if (keyDocQuery.docs.isNotEmpty) {
        expectedKey = keyDocQuery.docs.first.data()['key'] as String?;
      }
      if (expectedKey == null || expectedKey != qrSecurityKey) {
        _showErrorDialog('Security key mismatch. Please use a valid QR code.');
        setState(() => _isCheckingOut = false);
        return;
      }

      // --- LOCATION VALIDATION ---
      // Get office location from QR
      final qrLocation = qrMap['location'];
      if (qrLocation == null || qrLocation['latitude'] == null || qrLocation['longitude'] == null) {
        _showErrorDialog('QR code missing office location.');
        setState(() => _isCheckingOut = false);
        return;
      }
      final officeLat = (qrLocation['latitude'] as num).toDouble();
      final officeLng = (qrLocation['longitude'] as num).toDouble();
      final allowedDistance = _allowedDistance;

      // Get employee current location
      Position? position;
      String address = 'Unknown Location';
      try {
        position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        _showErrorDialog('Could not fetch your location.');
        setState(() => _isCheckingOut = false);
        return;
      }

      // Check if checked in today and not already checked out
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);
      final docRef = FirebaseFirestore.instance.collection('attendance').doc('${widget.email}_$dateId');
      final existingAttendance = await docRef.get();
      if (!existingAttendance.exists || existingAttendance.data()!['checkInTime'] == null) {
        _showErrorDialog('You must check in before checking out.');
        setState(() => _isCheckingOut = false);
        return;
      }
      if (existingAttendance.data()!['checkOutTime'] != null) {
        _showErrorDialog('Already checked out today.');
        setState(() => _isCheckingOut = false);
        return;
      }

      // Calculate distance
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, officeLat, officeLng);
      if (distance > allowedDistance) {
        // --- REJECTED CHECK-OUT ---
        await docRef.update({
          'checkOutTime': Timestamp.fromDate(now),
          'status': 'rejected_checkout',
          'remark': 'Rejected: Not in office location for check-out',
          'checkout_location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'address': address,
            'distance': distance,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'heading': position.heading,
          },
          'office_location': {
            'latitude': officeLat,
            'longitude': officeLng,
            'address': qrLocation['Long Description'] ?? '',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _showErrorDialog('You are not in the office location. Check-out rejected.');
        setState(() => _isCheckingOut = false);
        return;
      }

      // --- VALID CHECK-OUT ---
      final checkInTimestamp = existingAttendance.data()!['checkInTime'];
      DateTime checkInTime = checkInTimestamp is Timestamp ? checkInTimestamp.toDate() : now;
      await docRef.update({
        'checkOutTime': Timestamp.fromDate(now),
        'status': 'present',
        'updatedBy': widget.email,
        'updatedAt': FieldValue.serverTimestamp(),
        'workDuration': _calculateWorkDuration(checkInTime, now),
        'checkout_location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'address': address,
          'distance': distance,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'speed': position.speed,
          'heading': position.heading,
        },
        'office_location': {
          'latitude': officeLat,
          'longitude': officeLng,
          'address': qrLocation['Long Description'] ?? '',
        },
      });

      setState(() {
        _lastCheckOutTime = now;
        _currentStatus = 'Checked Out';
        _isCheckingOut = false;
      });

      _showSuccessDialog(
        'Successfully checked out at \\${DateFormat('HH:mm').format(now)}!',
        Colors.green,
      );
    } catch (e) {
      setState(() => _isCheckingOut = false);
      _showErrorDialog('Error processing QR code: $e');
    }
  }

  Future<void> _performCheckInWithoutLocation() async {
    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final lateThreshold = DateTime(now.year, now.month, now.day, 10, 15);
      final halfDayThreshold = DateTime(now.year, now.month, now.day, 12, 0);
      String status = 'present';
      String remark = 'QR check-in';
      bool isLate = false;
      bool isHalfDay = false;

      if (now.isAfter(halfDayThreshold)) {
        status = 'half-day';
        remark = 'QR check-in after 12:00 PM (Half Day)';
        isHalfDay = true;
      } else if (now.isAfter(lateThreshold)) {
        status = 'late';
        remark = 'QR check-in after 10:15 AM (Late)';
        isLate = true;
      }

      // Create date-based document ID
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);

      // Check if already checked in today
      final existingAttendance = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();

      if (existingAttendance.exists) {
        final existingRecord = existingAttendance.data()!;
        if (existingRecord['checkInTime'] != null) {
          _showErrorDialog('Already checked in today.');
          setState(() => _isCheckingIn = false);
          return;
        } else {
          // Update existing record
          await FirebaseFirestore.instance.collection('attendance').doc('${widget.email}_$dateId').update({
            'checkInTime': Timestamp.fromDate(now),
            'status': status,
            'remark': remark,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // Add new record
        await FirebaseFirestore.instance.collection('attendance').add({
          'email': widget.email,
          'date': Timestamp.fromDate(dateOnly),
          'date_id': dateId,
          'checkInTime': Timestamp.fromDate(now),
          'status': status,
          'markedby': widget.email,
          'remark': remark,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      setState(() {
        _lastCheckInTime = now;
        _currentStatus = isHalfDay ? 'Half Day' : isLate ? 'Late' : 'Checked In';
        _isCheckingIn = false;
      });

      _showSuccessDialog(
        isHalfDay
            ? 'Checked in after 12:00 PM (Half Day)!'
            : isLate
            ? 'Checked in after 10:15 AM (Late)!'
            : 'Successfully checked in at ${DateFormat('HH:mm').format(now)}!',
        isHalfDay || isLate ? Colors.orange : Colors.green,
      );

    } catch (e) {
      setState(() => _isCheckingIn = false);
      _showErrorDialog('Error checking in: $e');
    }
  }

  Future<void> _performCheckOutWithoutLocation() async {
    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);

      // Check if checked in today
      final existingAttendance = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();

      if (!existingAttendance.exists || existingAttendance.data()!['checkInTime'] == null) {
        _showErrorDialog('Please check in first.');
        setState(() => _isCheckingOut = false);
        return;
      }

      final existingRecord = existingAttendance.data()!;
      if (existingRecord['checkOutTime'] != null) {
        _showErrorDialog('Already checked out today.');
        setState(() => _isCheckingOut = false);
        return;
      }

      // Update attendance record with checkout time
      final checkInTimestamp = existingRecord['checkInTime'];
      DateTime checkInTime = checkInTimestamp is Timestamp ? checkInTimestamp.toDate() : DateTime.now();

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .update({
        'checkOutTime': Timestamp.fromDate(now),
        'status': 'present',
        'updatedBy': widget.email,
        'updatedAt': FieldValue.serverTimestamp(),
        'workDuration': _calculateWorkDuration(checkInTime, now),
      });

      setState(() {
        _lastCheckOutTime = now;
        _currentStatus = 'Checked Out';
        _isCheckingOut = false;
      });

      _showSuccessDialog(
        'Successfully checked out at ${DateFormat('HH:mm').format(now)}!',
        Colors.green,
      );

    } catch (e) {
      setState(() => _isCheckingOut = false);
      _showErrorDialog('Error checking out: $e');
    }
  }

  void _showSuccessDialog(String message, Color color) {
    final media = MediaQuery.of(context);
    final fontScale = media.size.width < 400 ? 0.85 : media.size.width < 600 ? 0.95 : 1.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: color, size: 28 * fontScale),
            SizedBox(width: 8 * (media.size.width / 100)),
            Expanded(
              child: Text(
                'Success',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18 * fontScale,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: 16 * fontScale),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadCurrentAttendanceStatus(); // Refresh status
            },
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14 * fontScale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    final media = MediaQuery.of(context);
    final fontScale = media.size.width < 400 ? 0.85 : media.size.width < 600 ? 0.95 : 1.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28 * fontScale),
            SizedBox(width: 8 * (media.size.width / 100)),
            Expanded(
              child: Text(
                'Error',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18 * fontScale,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(fontSize: 16 * fontScale),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              'OK',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14 * fontScale,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminAttendanceBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Header with date and search
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.calendar_today),
                        label: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _selectedDate,
                            firstDate: DateTime.now().subtract(const Duration(days: 365)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() => _selectedDate = picked);
                            _fetchEmployeesAndAttendance();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Search employees...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Bulk actions
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markAll(0),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                        child: const Text('Mark All Present'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markAll(1),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text('Mark All Absent'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _markAll(2),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        child: const Text('Mark All Leave'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // QR Code Management Section with Dropdown
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'QR Code Attendance Management',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Display selected office address
                      Text(
                        _selectedCompanyLocation?['Long Description'] ?? _officeLocation ?? 'Please select a location.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _isGeneratingQR
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,))
                                  : const Icon(Icons.qr_code),
                              label: Text(_isGeneratingQR ? 'Generating...' : 'Generate QR Code'),
                              onPressed: _isGeneratingQR || _selectedCompanyLocation == null ? null : _generateQRCode,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.location_on),
                              label: const Text('Configure Location'),
                              onPressed: _configureOfficeLocation,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Location Dropdown
                      DropdownButtonFormField<Map<String, dynamic>>(
                        value: _selectedCompanyLocation,
                        items: _companyLocations.map((loc) {
                          return DropdownMenuItem<Map<String, dynamic>>(
                            value: loc,
                            child: Text(loc['Value1'] ?? 'Unnamed Location'),
                          );
                        }).toList(),
                        onChanged: (newValue) {
                          setState(() {
                            _selectedCompanyLocation = newValue;
                            _officeLocation = _selectedCompanyLocation?['Long Description'];
                            _officeLatitude = _selectedCompanyLocation?['latitude']?.toDouble();
                            _officeLongitude = _selectedCompanyLocation?['longitude']?.toDouble();
                            _qrData = null; // Invalidate QR code on location change
                            // Automatically set the security key from the selected location
                            _selectedSecurityKey = _selectedCompanyLocation?['security_key'] ?? '';
                          });
                        },
                        decoration: const InputDecoration(
                          labelText: 'Select Office Location',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                      ),
                      if (_qrData != null) ...[
                        const SizedBox(height: 16),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              children: [
                                QrImageView(
                                  data: _qrData!,
                                  version: QrVersions.auto,
                                  size: 200.0,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Scan this QR code for attendance',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Scrollable employee list and actions
          if (widget.isAdmin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text('View History'),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _AttendanceHistoryScreen(
                            email: widget.email,
                            isAdmin: true,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export as PDF'),
                    onPressed: _exportAttendanceAsPdf,
                  ),
                ],
              ),
            ),
          // DataTable scrollable horizontally
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Name', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Check In', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Check Out', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Present', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Absent', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Leave', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _filteredEmployees.map((user) {
                final email = user['email'];
                final statusIdx = _attendanceStatus[email];
                final todayRecord = _attendanceRecords.firstWhere(
                      (rec) => rec['email'] == email,
                  orElse: () => <String, dynamic>{},
                );
                return DataRow(
                  cells: [
                    DataCell(Text(user['name'] ?? user['firstName'] ?? user['email'] ?? '')),
                    DataCell(Text(user['email'] ?? '')),
                    DataCell(Text(_formatDateTimeField(todayRecord['checkInTime']))),
                    DataCell(Text(_formatDateTimeField(todayRecord['checkOutTime']))),
                    DataCell(Checkbox(
                      value: statusIdx == 0,
                      onChanged: _saving ? null : (bool? value) {
                        setState(() {
                          if (value == true) {
                            _attendanceStatus[email] = 0;
                          } else if (statusIdx == 0) {
                            _attendanceStatus[email] = null;
                          }
                        });
                      },
                    )),
                    DataCell(Checkbox(
                      value: statusIdx == 1,
                      onChanged: _saving ? null : (bool? value) {
                        setState(() {
                          if (value == true) {
                            _attendanceStatus[email] = 1;
                          } else if (statusIdx == 1) {
                            _attendanceStatus[email] = null;
                          }
                        });
                      },
                    )),
                    DataCell(Checkbox(
                      value: statusIdx == 2,
                      onChanged: _saving ? null : (bool? value) {
                        setState(() {
                          if (value == true) {
                            _attendanceStatus[email] = 2;
                          } else if (statusIdx == 2) {
                            _attendanceStatus[email] = null;
                          }
                        });
                      },
                    )),
                    DataCell(Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_saving)
                          ElevatedButton(
                            onPressed: _saving ? null : _saveAttendance,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            ),
                            child: const Text('Save'),
                          ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: _saving ? null : () => _editAttendanceDialog(todayRecord),
                        ),
                      ],
                    )),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAttendanceAsPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Attendance History', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('S.No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Email', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Check In', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Check Out', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...List.generate(_attendanceRecords.length, (index) {
                    final record = _attendanceRecords[index];
                    final name = _employees.firstWhere((emp) => emp['email'] == record['email'], orElse: () => {})['name'] ?? '';
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text('${index + 1}'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(name),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(record['email'] ?? ''),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text((record['status'] ?? '').toString().toUpperCase()),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_formatDateTimeField(record['checkInTime'])),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_formatDateTimeField(record['checkOutTime'])),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // QR Code Methods
  Future<void> _loadOfficeLocation() async {
    try {
      // Load office location from database
      final locationDoc = await FirebaseFirestore.instance
          .collection('office_location')
          .doc('main_office')
          .get();

      if (locationDoc.exists) {
        final data = locationDoc.data()!;
        setState(() {
          _officeLocation = data['address'] ?? 'Office Location';
          _officeLatitude = data['latitude']?.toDouble();
          _officeLongitude = data['longitude']?.toDouble();
          _allowedDistance = data['allowed_distance']?.toDouble() ?? 100.0;
        });
      } else {
        // Set default location if not configured
        setState(() {
          _officeLocation = 'Office Location (Not Configured)';
          _officeLatitude = 0.0;
          _officeLongitude = 0.0;
        });
      }
    } catch (e) {
      print('Error loading office location: $e');
    }
  }

  // Generate QR Code (Admin only)
  Future<void> _generateQRCode() async {
    if (_isGeneratingQR) return;
    if (!widget.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only administrators can generate QR codes.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_selectedCompanyLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a company location.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final loc = _selectedCompanyLocation!;
    final value1 = loc['Value1']?.toString() ?? 'unknown';
    final latitude = (loc['latitude'] is num) ? loc['latitude'].toString() : '0.0';
    final longitude = (loc['longitude'] is num) ? loc['longitude'].toString() : '0.0';
    final type = loc['type']?.toString() ?? 'location';
    final longDesc = loc['Long Description']?.toString() ?? '';
    setState(() => _isGeneratingQR = true);
    try {
      final now = DateTime.now();
      final securityKey = await _getOrCreateSecurityKeyForToday(loc);
      if (securityKey.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No security key found for this location.'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isGeneratingQR = false);
        return;
      }
      final qrData = {
        'type': 'attendance_checkin',
        'date': DateFormat('yyyy-MM-dd').format(now),
        'generated_by': widget.email,
        'timestamp': now.millisecondsSinceEpoch,
        'location': {
          'Value1': value1,
          'latitude': double.tryParse(latitude) ?? 0.0,
          'longitude': double.tryParse(longitude) ?? 0.0,
          'type': type,
          'Long Description': longDesc,
        },
        'security_key': securityKey,
      };
      setState(() {
        _qrData = jsonEncode(qrData);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR Code generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating QR code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isGeneratingQR = false);
    }
  }

  Future<String> _getOrCreateSecurityKeyForToday(Map<String, dynamic> loc) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final value1 = loc['Value1']?.toString() ?? 'unknown';
    final latitude = loc['latitude']?.toString() ?? '0.0';
    final longitude = loc['longitude']?.toString() ?? '0.0';
    final keyDocQuery = await FirebaseFirestore.instance
        .collection('codes_master')
        .where('type', isEqualTo: 'attendance_security_key')
        .where('date', isEqualTo: dateStr)
        .where('Value1', isEqualTo: value1)
        .where('latitude', isEqualTo: double.tryParse(latitude) ?? 0.0)
        .where('longitude', isEqualTo: double.tryParse(longitude) ?? 0.0)
        .limit(1)
        .get();
    if (keyDocQuery.docs.isNotEmpty) {
      return keyDocQuery.docs.first.data()['key'] ?? '';
    } else {
      final key = _generateSecurityKey();
      await FirebaseFirestore.instance.collection('codes_master').add({
        'type': 'attendance_security_key',
        'date': dateStr,
        'Value1': value1,
        'latitude': double.tryParse(latitude) ?? 0.0,
        'longitude': double.tryParse(longitude) ?? 0.0,
        'key': key,
        'created_at': FieldValue.serverTimestamp(),
        'Active': true,
      });
      return key;
    }
  }

  String _generateSecurityKey() {
    const chars = '0123456789ABCDEF';
    final rand = List.generate(25, (_) => chars[(DateTime.now().microsecondsSinceEpoch + DateTime.now().millisecondsSinceEpoch + DateTime.now().second) % chars.length]).join();
    return rand;
  }

  Future<void> _startScanning() async {
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required for QR code attendance'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Location Permission Required'),
              content: const Text(
                'Location permissions are permanently denied. Please enable location permissions in your device settings to use QR code attendance.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Location Services Disabled'),
              content: const Text(
                'Please enable location services on your device to use QR code attendance.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      // Initialize scanner controller with error handling
      try {
        _scannerController = MobileScannerController(
          detectionSpeed: DetectionSpeed.normal,
          facing: CameraFacing.back,
          torchEnabled: false,
        );

        setState(() => _isScanning = true);
      } catch (scannerError) {
        if (mounted) {
          // Show fallback option when scanner fails
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Camera Access Issue'),
              content: const Text(
                'Unable to access camera for QR scanning. You can manually enter the QR code data or check camera permissions.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showManualQRInput();
                  },
                  child: const Text('Manual Input'),
                ),
              ],
            ),
          );
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting QR scanner: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _onQRViewCreated(MobileScannerController controller) {
    _scannerController = controller;
    controller.start();
  }

  void _onDetect(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        _processQRCode(barcode.rawValue!);
        break; // Process only the first barcode
      }
    }
  }

  Future<void> _processQRCode(String qrData) async {
    try {
      Map<String, dynamic> qrMap;
      try {
        qrMap = jsonDecode(qrData) as Map<String, dynamic>;
      } catch (e) {
        throw Exception('Invalid QR code format');
      }
      if (qrMap['type'] != 'attendance_checkin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code for attendance'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // Validate location from QR
      final qrLocation = qrMap['location'];
      if (qrLocation == null || qrLocation['latitude'] == null || qrLocation['longitude'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code missing location information.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      // For employees only: Validate location before processing QR
      if (!widget.isAdmin) {
        final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          (qrLocation['latitude'] as num).toDouble(),
          (qrLocation['longitude'] as num).toDouble(),
        );
        const allowedDistance = 100.0;
        if (distance > allowedDistance) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.location_off, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Too Far From Office'),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
                  child: Text('You are \\${distance.toStringAsFixed(0)} meters away from the office. Maximum allowed: \\${allowedDistance.toStringAsFixed(0)} meters.'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        // Show success dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.location_on, color: Colors.green),
                SizedBox(width: 8),
                Text('Location Validated'),
              ],
            ),
            content: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
                child: Text('Distance from office: \\${distance.toStringAsFixed(0)} meters\\nProceeding with attendance...'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  // Fetch employee address
                  String employeeAddress = 'Unknown Location';
                  try {
                    List<Placemark> placemarks = await placemarkFromCoordinates(
                      position.latitude,
                      position.longitude,
                    );
                    if (placemarks.isNotEmpty) {
                      Placemark place = placemarks[0];
                      employeeAddress = [
                        place.street,
                        place.subLocality,
                        place.locality,
                        place.administrativeArea,
                        place.postalCode,
                        place.country,
                      ].where((element) => element != null && element.isNotEmpty).join(', ');
                    }
                  } catch (e) {
                    print('Error getting address: $e');
                  }
                  // Prepare office address
                  String officeAddress = 'Unknown Office Location';
                  if (qrLocation['Long Description'] != null && qrLocation['Long Description'].toString().isNotEmpty) {
                    officeAddress = qrLocation['Long Description'];
                  }
                  // Prepare attendance record
                  final now = DateTime.now();
                  final dateOnly = DateTime(now.year, now.month, now.day);
                  final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);
                  final docId = '${widget.email}_$dateId';
                  final userSnap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: widget.email).limit(1).get();
                  final userData = userSnap.docs.isNotEmpty ? userSnap.docs.first.data() : {};
                  final name = userData['name'] ?? userData['firstName'] ?? widget.email;
                  final attendanceDoc = await FirebaseFirestore.instance.collection('attendance').doc(docId).get();
                  if (attendanceDoc.exists) {
                    // If already checked in, update checkout
                    await FirebaseFirestore.instance.collection('attendance').doc(docId).update({
                      'checkout_time': Timestamp.fromDate(now),
                      'updated_by': widget.email,
                      'updated_on': FieldValue.serverTimestamp(),
                      'employee_location': {
                        'latitude': position.latitude,
                        'longitude': position.longitude,
                        'address': employeeAddress,
                      },
                      'office_location': {
                        'latitude': qrLocation['latitude'],
                        'longitude': qrLocation['longitude'],
                        'address': officeAddress,
                      },
                    });
                  } else {
                    // New check-in
                    await FirebaseFirestore.instance.collection('attendance').doc(docId).set({
                      'email': widget.email,
                      'name': name,
                      'date_id': dateId,
                      'checkin_time': Timestamp.fromDate(now),
                      'created_by': widget.email,
                      'updated_by': widget.email,
                      'updated_on': FieldValue.serverTimestamp(),
                      'employee_location': {
                        'latitude': position.latitude,
                        'longitude': position.longitude,
                        'address': employeeAddress,
                      },
                      'office_location': {
                        'latitude': qrLocation['latitude'],
                        'longitude': qrLocation['longitude'],
                        'address': officeAddress,
                      },
                      'security_key': qrMap['security_key'],
                    });
                  }
                  _loadCurrentAttendanceStatus();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Attendance recorded successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        return;
      }
      // For admin, just show a success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR code processed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing QR code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _recordQRAttendance(Position position, double distance, {String? securityKey}) async {
    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);
      String address = 'Unknown Location';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        print('Error getting address: $e');
      }
      final existingAttendance = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();
      if (existingAttendance.exists) {
        final data = existingAttendance.data()!;
        if (data['checkin_time'] != null && data['checkout_time'] == null) {
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc('${widget.email}_$dateId')
              .update({
            'checkout_time': Timestamp.fromDate(now),
            'checkout_location': {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'distance': distance,
              'address': address,
              'accuracy': position.accuracy,
              'altitude': position.altitude,
              'speed': position.speed,
              'heading': position.heading,
            },
            'security_key': securityKey,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          if (mounted) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.logout, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Check-out Successful'),
                  ],
                ),
                content: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
                    child: const Text('You have checked out successfully.'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _loadCurrentAttendanceStatus();
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        } else if (data['checkin_time'] != null && data['checkout_time'] != null) {
          if (mounted) {
            await showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('Attendance Complete'),
                  ],
                ),
                content: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
                    child: const Text('You have already completed attendance for today.'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      } else {
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc('${widget.email}_$dateId')
            .set({
          'email': widget.email,
          'date': Timestamp.fromDate(dateOnly),
          'date_id': dateId,
          'checkin_time': Timestamp.fromDate(now),
          'status': 'present',
          'markedby': widget.email,
          'remark': 'QR Code Check-in',
          'checkin_location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'distance': distance,
            'address': address,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'heading': position.heading,
          },
          'security_key': securityKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.login, color: Colors.green),
                  SizedBox(width: 8),
                  Text('Check-in Successful'),
                ],
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
                  child: const Text('You have checked in successfully.'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _loadCurrentAttendanceStatus();
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording attendance: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _configureOfficeLocation() async {
    final addressController = TextEditingController(text: _officeLocation ?? '');
    final latController = TextEditingController(text: _officeLatitude?.toString() ?? '');
    final lngController = TextEditingController(text: _officeLongitude?.toString() ?? '');
    final distanceController = TextEditingController(text: _allowedDistance.toString());
    final locationNameController = TextEditingController(text: 'Main Office');
    final streetController = TextEditingController();
    final cityController = TextEditingController();
    final stateController = TextEditingController();
    final postalCodeController = TextEditingController();
    final countryController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Configure Office Location'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Get Current Location Button
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    // Request location permission
                    LocationPermission permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                      if (permission == LocationPermission.denied) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Location permission is required'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                    }

                    if (permission == LocationPermission.deniedForever) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Location permissions are permanently denied'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    // Get current position
                    final position = await Geolocator.getCurrentPosition(
                      desiredAccuracy: LocationAccuracy.high,
                    );

                    // Get address from coordinates
                    List<Placemark> placemarks = await placemarkFromCoordinates(
                      position.latitude,
                      position.longitude,
                    );

                    if (placemarks.isNotEmpty) {
                      Placemark place = placemarks[0];
                      latController.text = position.latitude.toString();
                      lngController.text = position.longitude.toString();
                      streetController.text = place.street ?? '';
                      cityController.text = place.locality ?? '';
                      stateController.text = place.administrativeArea ?? '';
                      postalCodeController.text = place.postalCode ?? '';
                      countryController.text = place.country ?? '';

                      // Update address field
                      final fullAddress = [
                        place.street,
                        place.subLocality,
                        place.locality,
                        place.administrativeArea,
                        place.postalCode,
                        place.country,
                      ].where((element) => element != null && element.isNotEmpty).join(', ');
                      addressController.text = fullAddress;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Location captured successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error getting location: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.my_location),
                label: const Text('Get Current Location'),
              ),
              const SizedBox(height: 16),

              // Location Name
              TextField(
                controller: locationNameController,
                decoration: const InputDecoration(
                  labelText: 'Location Name',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Main Office, Branch Office',
                ),
              ),
              const SizedBox(height: 16),

              // Address Fields
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Full Office Address',
                  border: OutlineInputBorder(),
                  hintText: 'Enter complete office address',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: streetController,
                      decoration: const InputDecoration(
                        labelText: 'Street Address',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cityController,
                      decoration: const InputDecoration(
                        labelText: 'City',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: stateController,
                      decoration: const InputDecoration(
                        labelText: 'State/Province',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: postalCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Postal Code',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: countryController,
                      decoration: const InputDecoration(
                        labelText: 'Country',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Coordinates
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: latController,
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lngController,
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextField(
                controller: distanceController,
                decoration: const InputDecoration(
                  labelText: 'Allowed Distance (meters)',
                  border: OutlineInputBorder(),
                  hintText: 'Default: 100 meters',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        // Build full address from components if address field is empty
        String fullAddress = addressController.text;
        if (fullAddress.isEmpty) {
          fullAddress = [
            streetController.text,
            cityController.text,
            stateController.text,
            postalCodeController.text,
            countryController.text,
          ].where((element) => element.isNotEmpty).join(', ');
        }

        // Save to both office_location collection and codes_master collection
        final locationData = {
          'address': fullAddress,
          'street': streetController.text,
          'city': cityController.text,
          'state': stateController.text,
          'postal_code': postalCodeController.text,
          'country': countryController.text,
          'latitude': double.tryParse(latController.text) ?? 0.0,
          'longitude': double.tryParse(lngController.text) ?? 0.0,
          'allowed_distance': double.tryParse(distanceController.text) ?? 100.0,
          'updated_by': widget.email,
          'updated_at': FieldValue.serverTimestamp(),
        };

        // Save to office_location collection (for backward compatibility)
        await FirebaseFirestore.instance
            .collection('office_location')
            .doc('main_office')
            .set(locationData);

        // Save to codes_master collection (for integration with code master)
        await FirebaseFirestore.instance
            .collection('codes_master')
            .add({
          'type': 'company location',
          'Short Description': locationNameController.text,
          'Long Description': fullAddress,
          'Value1': locationNameController.text,
          'address': fullAddress,
          'latitude': double.tryParse(latController.text) ?? 0.0,
          'longitude': double.tryParse(lngController.text) ?? 0.0,
          'allowed_distance': double.tryParse(distanceController.text) ?? 100.0,
          'Active': true,
          'created_by': widget.email,
          'created_at': FieldValue.serverTimestamp(),
          'updated_by': widget.email,
          'updated_at': FieldValue.serverTimestamp(),
        });

        await _loadOfficeLocation();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Office location updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating office location: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showManualQRInput() {
    final qrController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manual QR Code Input'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the QR code data manually:'),
            const SizedBox(height: 16),
            TextField(
              controller: qrController,
              decoration: const InputDecoration(
                labelText: 'QR Code Data',
                border: OutlineInputBorder(),
                hintText: 'Paste QR code data here...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (qrController.text.isNotEmpty) {
                Navigator.pop(context);
                _processQRCode(qrController.text);
              }
            },
            child: const Text('Process'),
          ),
        ],
      ),
    );
  }

  // Build employee attendance section
  Widget _buildEmployeeAttendanceSection() {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;

    return Column(
      children: [
        // Current status card
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Current Status: $_currentStatus',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Current Time: ${_formatTimeForDisplay(_currentTime)}',
                  style: const TextStyle(fontSize: 16),
                ),
                if (_lastCheckInTime != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Check-in Time: ${_formatTimeForDisplay(_lastCheckInTime!)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
                if (_lastCheckOutTime != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Check-out Time: ${_formatTimeForDisplay(_lastCheckOutTime!)}',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isCheckingIn ? null : _handleCheckIn,
                  icon: _isCheckingIn
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: Text(_isCheckingIn ? 'Checking In...' : 'Check In'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isCheckingOut ? null : _handleCheckOut,
                  icon: _isCheckingOut
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.logout),
                  label: Text(_isCheckingOut ? 'Checking Out...' : 'Check Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),

        // QR Code section in employee view - Only show scan button, not generate
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'QR Code Attendance',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              SizedBox(height: block * 2),
              Text(
                _officeLocation ?? 'Office location not configured',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              SizedBox(height: block * 4),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _isScanning
                      ? SizedBox(
                    width: block * 4,
                    height: block * 4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.qr_code_scanner),
                  label: Text(_isScanning ? 'Scanning...' : 'Scan QR Code', style: TextStyle(fontSize: 16 * fontScale)),
                  onPressed: _isScanning ? null : _startScanning,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: block * 3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(block * 2),
                    ),
                  ),
                ),
              ),
              if (_isScanning) ...[
                SizedBox(height: block * 4),
                SizedBox(
                  height: block * 60,
                  child: Stack(
                    children: [
                      MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: block * 12,
                                ),
                                SizedBox(height: block * 4),
                                Text(
                                  'Camera Error: ${error.errorDetails?.message ?? 'Unknown error'}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.red, fontSize: 14 * fontScale),
                                ),
                                SizedBox(height: block * 4),
                                ElevatedButton(
                                  onPressed: () {
                                    setState(() => _isScanning = false);
                                    _scannerController?.dispose();
                                  },
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      Positioned(
                        top: block * 2,
                        right: block * 2,
                        child: FloatingActionButton(
                          onPressed: () {
                            setState(() => _isScanning = false);
                            _scannerController?.dispose();
                          },
                          backgroundColor: Colors.red,
                          mini: true,
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // REMOVED View Attendance History Button and Location Status Card
      ],
    );
  }

  // Employee check-in functionality
  Future<void> _handleCheckIn() async {
    if (_isCheckingIn) return;

    // For employees only: Validate location before allowing check-in
    if (!widget.isAdmin) {
      final locationValid = await _validateEmployeeLocationForCheckIn();
      if (!locationValid) {
        return; // Location validation failed, alert already shown
      }
    }

    setState(() => _isCheckingIn = true);

    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);
      final lateThreshold = DateTime(now.year, now.month, now.day, 10, 15);
      final halfDayThreshold = DateTime(now.year, now.month, now.day, 12, 0);
      String status = 'present';
      String remark = 'Self check-in';
      bool isLate = false;
      bool isHalfDay = false;

      if (now.isAfter(halfDayThreshold)) {
        status = 'half-day';
        remark = 'Checked in after 12:00 PM (Half Day)';
        isHalfDay = true;
      } else if (now.isAfter(lateThreshold)) {
        status = 'late';
        remark = 'Checked in after 10:15 AM (Late)';
        isLate = true;
      }

      // Create date-based document ID
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);

      // Get current location
      Position? position;
      String address = 'Unknown Location';
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // Get address from coordinates
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        print('Error getting location: $e');
      }

      // Check if already checked in today using date-based ID
      final existingAttendance = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();

      if (existingAttendance.exists) {
        final existingRecord = existingAttendance.data()!;
        if (existingRecord['checkInTime'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Already checked in today.'),
              backgroundColor: Colors.orange,
            ),
          );
          setState(() => _isCheckingIn = false);
          return;
        } else {
          // Update the existing record with check-in info
          await FirebaseFirestore.instance
              .collection('attendance')
              .doc('${widget.email}_$dateId')
              .update({
            'checkInTime': Timestamp.fromDate(now),
            'status': status,
            'remark': remark,
            'checkin_location': position != null ? {
              'latitude': position.latitude,
              'longitude': position.longitude,
              'address': address,
              'accuracy': position.accuracy,
              'altitude': position.altitude,
              'speed': position.speed,
              'heading': position.heading,
            } : null,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        // Add new record with date-based ID
        await FirebaseFirestore.instance
            .collection('attendance')
            .doc('${widget.email}_$dateId')
            .set({
          'email': widget.email,
          'date': Timestamp.fromDate(dateOnly),
          'date_id': dateId,
          'checkInTime': Timestamp.fromDate(now),
          'status': status,
          'markedby': widget.email,
          'remark': remark,
          'checkin_location': position != null ? {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'address': address,
            'accuracy': position.accuracy,
            'altitude': position.altitude,
            'speed': position.speed,
            'heading': position.heading,
          } : null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Check for 3 continuous late days
      if (isLate) {
        final lateQuery = await FirebaseFirestore.instance
            .collection('attendance')
            .where('email', isEqualTo: widget.email)
            .where('status', isEqualTo: 'late')
            .orderBy('date', descending: true)
            .limit(3)
            .get();
        if (lateQuery.docs.length == 3) {
          // Check if the last 3 records are for consecutive days
          List<DateTime> lateDates = lateQuery.docs.map((doc) {
            final ts = doc['date'];
            return ts is Timestamp ? ts.toDate() : DateTime.now();
          }).toList();
          lateDates.sort();
          bool isContinuous = true;
          for (int i = 1; i < lateDates.length; i++) {
            if (lateDates[i].difference(lateDates[i - 1]).inDays != 1) {
              isContinuous = false;
              break;
            }
          }
          if (isContinuous) {
            // Notify HR (for now, print debug message)
            debugPrint('Notify HR: ${widget.email} has 3 continuous late days!');
            // You can add logic to send an email/notification to HR here
          }
        }
      }

      setState(() {
        _lastCheckInTime = now;
        _currentStatus = isHalfDay ? 'Half Day' : isLate ? 'Late' : 'Checked In';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              isHalfDay
                  ? 'Checked in after 12:00 PM (Half Day)!'
                  : isLate
                  ? 'Checked in after 10:15 AM (Late)!'
                  : 'Checked in successfully at ${DateFormat('HH:mm').format(now)}!'),
          backgroundColor: isHalfDay || isLate ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking in: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isCheckingIn = false);
    }
  }

  // Employee check-out functionality
  Future<void> _handleCheckOut() async {
    if (_isCheckingOut) return;

    // For employees only: Validate location before allowing check-out
    if (!widget.isAdmin) {
      final locationValid = await _validateEmployeeLocationForCheckIn();
      if (!locationValid) {
        return; // Location validation failed, alert already shown
      }
    }

    setState(() => _isCheckingOut = true);

    try {
      final now = DateTime.now();
      final dateOnly = DateTime(now.year, now.month, now.day);

      // Create date-based document ID
      final dateId = DateFormat('yyyy-MM-dd').format(dateOnly);

      // Get current location
      Position? position;
      String address = 'Unknown Location';
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        // Get address from coordinates
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        print('Error getting location: $e');
      }

      // Check if checked in today using date-based ID
      final existingAttendance = await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .get();

      if (!existingAttendance.exists || existingAttendance.data()!['checkInTime'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please check in first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final existingRecord = existingAttendance.data()!;
      if (existingRecord['checkOutTime'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Already checked out today.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Update attendance record with checkout time and set status to present
      final checkInTimestamp = existingRecord['checkInTime'];
      DateTime checkInTime = checkInTimestamp is Timestamp ? checkInTimestamp.toDate() : DateTime.now();
      await FirebaseFirestore.instance
          .collection('attendance')
          .doc('${widget.email}_$dateId')
          .update({
        'checkOutTime': Timestamp.fromDate(now),
        'status': 'present', // Ensure present after check-out
        'updatedBy': widget.email,
        'updatedAt': FieldValue.serverTimestamp(),
        'workDuration': _calculateWorkDuration(checkInTime, now),
        'checkout_location': position != null ? {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'address': address,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'speed': position.speed,
          'heading': position.heading,
        } : null,
      });

      setState(() {
        _lastCheckOutTime = now;
        _currentStatus = 'Checked Out';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checked out successfully at ${DateFormat('HH:mm').format(now)}!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking out: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isCheckingOut = false);
    }
  }

  // Validate employee location for check-in/check-out (popup alert version)
  Future<bool> _validateEmployeeLocationForCheckIn() async {
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationPermissionAlert();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationPermissionAlert();
        return false;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address from coordinates
      String address = 'Unknown Location';
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = [
            place.street,
            place.subLocality,
            place.locality,
            place.administrativeArea,
            place.postalCode,
            place.country,
          ].where((element) => element != null && element.isNotEmpty).join(', ');
        }
      } catch (e) {
        print('Error getting address: $e');
      }

      // Get company location from code master
      final companyLocationQuery = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'company location')
          .where('Active', isEqualTo: true)
          .limit(1)
          .get();

      if (companyLocationQuery.docs.isEmpty) {
        _showLocationConfigAlert();
        return false;
      }

      final companyLocation = companyLocationQuery.docs.first.data();
      final officeLat = companyLocation['latitude'] as double?;
      final officeLng = companyLocation['longitude'] as double?;
      final allowedDistance = companyLocation['allowed_distance'] as double?;

      if (officeLat == null || officeLng == null || allowedDistance == null) {
        _showLocationConfigAlert();
        return false;
      }

      // Calculate distance
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat,
        officeLng,
      );

      // Show alert if employee is too far from office
      if (distance > allowedDistance) {
        _showLocationAlert(distance, allowedDistance, companyLocation, address);
        return false;
      }

      return true;

    } catch (e) {
      print('Error validating location: $e');
      _showLocationErrorAlert();
      return false;
    }
  }

  // Show location permission alert
  void _showLocationPermissionAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Location Permission Required', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Location permission is required for attendance validation.'),
                SizedBox(height: 8),
                Text('Please enable location services in your device settings to continue.'),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show location configuration alert
  void _showLocationConfigAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Office Location Not Configured', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Company office location is not configured in the system.'),
                SizedBox(height: 8),
                Text('Please contact your administrator to configure the office location.'),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show location error alert
  void _showLocationErrorAlert() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Location Error', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width * 0.6),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unable to get your current location.'),
                SizedBox(height: 8),
                Text('Please ensure location services are enabled and try again.'),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Show location alert when employee is too far from office
  void _showLocationAlert(double distance, double allowedDistance, Map<String, dynamic> companyLocation, String employeeAddress) async {
    final alertMessage = '''
🚫 Location Validation Failed!

You are ${distance.toStringAsFixed(0)} meters away from the office.
Maximum allowed distance: ${allowedDistance.toStringAsFixed(0)} meters.

Your current location: $employeeAddress
Office Address: ${companyLocation['address'] ?? 'Not specified'}

Please move closer to the office location to check in.
        ''';

    // Store failed attempt in Firebase
    try {
      final now = DateTime.now();
      final dateId = DateFormat('yyyy-MM-dd').format(now);
      await FirebaseFirestore.instance.collection('attendance_location_failures').add({
        'email': widget.email,
        'date': Timestamp.fromDate(now),
        'date_id': dateId,
        'distance': distance,
        'allowed_distance': allowedDistance,
        'employee_address': employeeAddress,
        'office_address': companyLocation['address'] ?? '',
        'latitude': companyLocation['latitude'] ?? '',
        'longitude': companyLocation['longitude'] ?? '',
        'created_at': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Ignore errors for logging
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.location_off, color: Colors.red, size: 28),
            SizedBox(width: 8),
            Text('Too Far From Office', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alertMessage),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ Important Notice:',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '• Attendance will only be recorded when you are within the allowed distance\n'
                            '• This helps ensure accurate attendance tracking\n'
                            '• Please contact your supervisor if you need to work from a different location',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // New method for admins to fetch company locations
  Future<void> _fetchCompanyLocations() async {
    if (!widget.isAdmin) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'company location')
          .where('Active', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _companyLocations = snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();
          if (_companyLocations.isNotEmpty) {
            _selectedCompanyLocation = _companyLocations.first;
          }
        });
      }
    } catch (e) {
      // Handle error
    }
  }

  // New method for employees to fetch and display their location
  Future<void> _fetchAndValidateEmployeeLocation() async {
    if (widget.isAdmin) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _employeeLocationAddress = 'Location permission denied.');
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      List<Placemark> placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      final address = placemarks.isNotEmpty ? placemarks.first.street : 'Unknown Address';

      // Validation part
      final companyLocationQuery = await FirebaseFirestore.instance.collection('codes_master').where('type', isEqualTo: 'company location').where('Active', isEqualTo: true).limit(1).get();

      if (companyLocationQuery.docs.isEmpty) {
        setState(() {
          _isLocationValid = false;
        });
        return;
      }
      final companyLocation = companyLocationQuery.docs.first.data();
      final officeLat = companyLocation['latitude'] as double?;
      final officeLng = companyLocation['longitude'] as double?;
      final allowedDistance = companyLocation['allowed_distance'] as double?;

      if(officeLat == null || officeLng == null || allowedDistance == null) {
        setState(() {
          _isLocationValid = false;
        });
        return;
      }

      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, officeLat, officeLng);

      if (mounted) {
        setState(() {
          _currentEmployeeLocation = position;
          _employeeLocationAddress = address ?? "Could not determine address.";
          _distanceFromOffice = distance;
          _isLocationValid = distance <= allowedDistance;
        });
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _employeeLocationAddress = 'Error fetching location.';
        });
      }
    }
  }

  Future<void> _fetchSecurityKeys() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'attendance_security_key')
          .where('Active', isEqualTo: true)
          .get();

      if (mounted) {
        setState(() {
          _availableSecurityKeys = snapshot.docs.map((doc) => doc.data()['key'] as String).toList();
          if (_availableSecurityKeys.isNotEmpty) {
            _selectedSecurityKey = _availableSecurityKeys.first;
          }
        });
      }
    } catch (e) {
      print('Error fetching security keys: $e');
    }
  }
}

// Replace _EmployeeAttendanceCalendar with a TableCalendar-based widget
class _EmployeeAttendanceCalendar extends StatefulWidget {
  final String email;
  final void Function(DateTime, Map<String, dynamic>? attendanceData) onDateSelected;
  const _EmployeeAttendanceCalendar({required this.email, required this.onDateSelected});

  @override
  State<_EmployeeAttendanceCalendar> createState() => _EmployeeAttendanceCalendarState();
}

class _EmployeeAttendanceCalendarState extends State<_EmployeeAttendanceCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, Map<String, dynamic>> _attendanceByDate = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAttendance();
  }

  Future<void> _fetchAttendance() async {
    setState(() => _loading = true);
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final end = DateTime(_focusedDay.year, _focusedDay.month + 1, 0);
    final snapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('email', isEqualTo: widget.email)
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    final map = <String, Map<String, dynamic>>{};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      if (data['date'] is Timestamp) {
        final dt = (data['date'] as Timestamp).toDate();
        final key = DateTime(dt.year, dt.month, dt.day);
        map['${key.year}-${key.month}-${key.day}'] = data;
      }
    }
    setState(() {
      _attendanceByDate = map;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return TableCalendar(
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        final key = '${selectedDay.year}-${selectedDay.month}-${selectedDay.day}';
        widget.onDateSelected(selectedDay, _attendanceByDate[key]);
      },
      calendarFormat: CalendarFormat.month,
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = focusedDay);
        _fetchAttendance();
      },
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, focusedDay) {
          final key = '${day.year}-${day.month}-${day.day}';
          final att = _attendanceByDate[key];
          Color? bg;
          if (att != null) {
            switch ((att['status'] ?? '').toLowerCase()) {
              case 'present':
                bg = Colors.green.withOpacity(0.2);
                break;
              case 'absent':
                bg = Colors.red.withOpacity(0.2);
                break;
              case 'leave':
                bg = Colors.orange.withOpacity(0.2);
                break;
              default:
                bg = Colors.grey.withOpacity(0.1);
            }
          }
          return Container(
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('${day.day}'),
          );
        },
      ),
    );
  }
}

// Add this widget at the end of the file
class _AdminAttendanceCalendar extends StatefulWidget {
  final void Function(DateTime) onDateSelected;
  const _AdminAttendanceCalendar({required this.onDateSelected});

  @override
  State<_AdminAttendanceCalendar> createState() => _AdminAttendanceCalendarState();
}

class _AdminAttendanceCalendarState extends State<_AdminAttendanceCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime.utc(2000, 1, 1),
      lastDay: DateTime.utc(2100, 12, 31),
      focusedDay: _focusedDay,
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (selectedDay, focusedDay) {
        setState(() {
          _selectedDay = selectedDay;
          _focusedDay = focusedDay;
        });
        widget.onDateSelected(selectedDay);
      },
      calendarFormat: CalendarFormat.month,
      onPageChanged: (focusedDay) {
        setState(() => _focusedDay = focusedDay);
      },
    );
  }
}

class AttendanceHistoryExportScreen extends StatefulWidget {
  const AttendanceHistoryExportScreen({super.key});

  @override
  _AttendanceHistoryExportScreenState createState() => _AttendanceHistoryExportScreenState();
}

class _AttendanceHistoryExportScreenState extends State<AttendanceHistoryExportScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _allAttendance = [];
  Map<String, String> _emailToName = {};

  @override
  void initState() {
    super.initState();
    _fetchAllAttendance();
  }

  Future<void> _fetchAllAttendance() async {
    setState(() => _loading = true);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final snapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(todayOnly))
        .orderBy('date', descending: false)
        .get();
    final List<Map<String, dynamic>> records = [];
    final Set<String> emails = {};
    for (var doc in snapshot.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      // Don't include admin records
      if (data['email'] != null && !(data['email'] as String).toLowerCase().contains('admin')) {
        records.add(data);
        emails.add(data['email']);
      }
    }
    // Fetch names for all unique emails
    final emailToName = <String, String>{};
    if (emails.isNotEmpty) {
      final emailList = emails.toList();
      for (int i = 0; i < emailList.length; i += 10) {
        final batch = emailList.skip(i).take(10).toList();
        final usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', whereIn: batch)
            .get();
        for (var doc in usersSnapshot.docs) {
          final user = doc.data();
          final email = user['email'];
          final name = user['displayName'] ?? user['name'] ?? user['firstName'] ?? '';
          if (email != null) emailToName[email] = name;
        }
      }
    }
    setState(() {
      _allAttendance = records;
      _emailToName = emailToName;
      _loading = false;
    });
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      return DateFormat('dd MMM yyyy').format(date.toDate());
    }
    if (date is DateTime) {
      return DateFormat('dd MMM yyyy').format(date);
    }
    return 'No Date';
  }

  String _formatTime(dynamic time) {
    if (time is Timestamp) {
      return DateFormat('HH:mm').format(time.toDate());
    }
    if (time is DateTime) {
      return DateFormat('HH:mm').format(time);
    }
    return '--:--';
  }

  String _formatLocation(Map<String, dynamic>? location) {
    if (location == null) return 'No location data';

    final address = location['address'] as String?;
    if (address != null && address.isNotEmpty) {
      return address;
    }

    final lat = location['latitude'] as double?;
    final lng = location['longitude'] as double?;
    if (lat != null && lng != null) {
      return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
    }

    return 'Location data incomplete';
  }

  String _getStatusDisplay(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'late':
        return 'Late';
      case 'half-day':
        return 'Half Day';
      case 'leave':
        return 'Leave';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'half-day':
        return Colors.amber;
      case 'leave':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance History'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 1200,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('S.No')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Check In')),
                DataColumn(label: Text('Check Out')),
              ],
              rows: List.generate(_allAttendance.length, (index) {
                final record = _allAttendance[index];
                final name = _emailToName[record['email']] ?? '';
                return DataRow(cells: [
                  DataCell(Text('${index + 1}')),
                  DataCell(Text(name)),
                  DataCell(Text(record['email'] ?? '')),
                  DataCell(Text(_formatDate(record['date']))),
                  DataCell(Text(_getStatusDisplay(record['status'] ?? ''))),
                  DataCell(Text(_formatTime(record['checkInTime']))),
                  DataCell(Text(_formatTime(record['checkOutTime'])))
                ]);
              }),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Export Attendance Report'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.today, color: Colors.blue),
                      title: const Text('Today'),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportTodayAttendance();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.view_week, color: Colors.green),
                      title: const Text('This Week'),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportThisWeekAttendance();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.calendar_month, color: Colors.orange),
                      title: const Text('This Month'),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportThisMonthAttendance();
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.date_range, color: Colors.purple),
                      title: const Text('All Records'),
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportAsPdf();
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
        icon: const Icon(Icons.picture_as_pdf),
        label: const Text('Export as PDF'),
      ),
    );
  }

  Future<void> _exportAsPdf() async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Attendance History', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              pw.Table(
                border: pw.TableBorder.all(),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('S.No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Email', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Check In', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8.0),
                        child: pw.Text('Check Out', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      ),
                    ],
                  ),
                  ...List.generate(_allAttendance.length, (index) {
                    final record = _allAttendance[index];
                    final name = _emailToName[record['email']] ?? '';
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text('${index + 1}'),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(name),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(record['email'] ?? ''),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_formatDate(record['date'])),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_getStatusDisplay(record['status'] ?? '')),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_formatTime(record['checkInTime'])),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(8.0),
                          child: pw.Text(_formatTime(record['checkOutTime'])),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // Helper methods for date calculations
  DateTime _getTodayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _getTodayEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  DateTime _getWeekStart() {
    final now = DateTime.now();
    final weekday = now.weekday;
    return DateTime(now.year, now.month, now.day - weekday + 1);
  }

  DateTime _getWeekEnd() {
    final now = DateTime.now();
    final weekday = now.weekday;
    return DateTime(now.year, now.month, now.day + (7 - weekday), 23, 59, 59);
  }

  DateTime _getMonthStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, 1);
  }

  DateTime _getMonthEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  }

  // Export methods for different time periods
  Future<void> _exportTodayAttendance() async {
    final startDate = _getTodayStart();
    final endDate = _getTodayEnd();
    await _exportAttendanceForDateRange(startDate, endDate, 'Today');
  }

  Future<void> _exportThisWeekAttendance() async {
    final startDate = _getWeekStart();
    final endDate = _getWeekEnd();
    await _exportAttendanceForDateRange(startDate, endDate, 'This Week');
  }

  Future<void> _exportThisMonthAttendance() async {
    final startDate = _getMonthStart();
    final endDate = _getMonthEnd();
    await _exportAttendanceForDateRange(startDate, endDate, 'This Month');
  }

  Future<void> _exportAttendanceForDateRange(DateTime startDate, DateTime endDate, String periodName) async {
    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Generating PDF...'),
            ],
          ),
        ),
      );

      // Fetch attendance records for the date range
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('date', descending: false)
          .get();

      final List<Map<String, dynamic>> records = [];
      final Set<String> emails = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        if (data['email'] != null && !(data['email'] as String).toLowerCase().contains('admin')) {
          records.add(data);
          emails.add(data['email']);
        }
      }

      // Fetch names for all unique emails
      final emailToName = <String, String>{};
      if (emails.isNotEmpty) {
        final emailList = emails.toList();
        for (int i = 0; i < emailList.length; i += 10) {
          final batch = emailList.skip(i).take(10).toList();
          final usersSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .where('email', whereIn: batch)
              .get();
          for (var doc in usersSnapshot.docs) {
            final user = doc.data();
            final email = user['email'];
            final name = user['displayName'] ?? user['name'] ?? user['firstName'] ?? '';
            if (email != null) emailToName[email] = name;
          }
        }
      }

      // Close loading dialog
      Navigator.of(context).pop();

      // Generate PDF
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          build: (context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Attendance Report - $periodName',
                    style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Text('Period: ${DateFormat('dd MMM yyyy').format(startDate)} - ${DateFormat('dd MMM yyyy').format(endDate)}',
                    style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 16),
                if (records.isEmpty)
                  pw.Text('No attendance records found for this period.',
                      style: pw.TextStyle(fontSize: 14, fontStyle: pw.FontStyle.italic))
                else
                  pw.Table(
                    border: pw.TableBorder.all(),
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('S.No', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Email', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Status', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Check In', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(8.0),
                            child: pw.Text('Check Out', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      ...List.generate(records.length, (index) {
                        final record = records[index];
                        final name = emailToName[record['email']] ?? '';
                        return pw.TableRow(
                          children: [
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text('${index + 1}'),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(name),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(record['email'] ?? ''),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(_formatDate(record['date'])),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(_getStatusDisplay(record['status'] ?? '')),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(_formatTime(record['checkInTime'])),
                            ),
                            pw.Padding(
                              padding: const pw.EdgeInsets.all(8.0),
                              child: pw.Text(_formatTime(record['checkOutTime'])),
                            ),
                          ],
                        );
                      }),
                    ],
                  ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF exported successfully for $periodName!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Attendance History Screen
class _AttendanceHistoryScreen extends StatefulWidget {
  final String email;
  final bool isAdmin;

  const _AttendanceHistoryScreen({
    required this.email,
    required this.isAdmin,
  });

  @override
  State<_AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<_AttendanceHistoryScreen> {
  List<Map<String, dynamic>> _attendanceRecords = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAttendanceHistory();
  }

  Future<void> _fetchAttendanceHistory() async {
    setState(() => _loading = true);
    try {
      Query query = FirebaseFirestore.instance.collection('attendance');

      if (widget.isAdmin) {
        // Admin can see all records
        query = query.orderBy('date', descending: true).limit(50);
      } else {
        // Employee sees only their records
        query = query.where('email', isEqualTo: widget.email)
            .orderBy('date', descending: true)
            .limit(30);
      }

      final snapshot = await query.get();
      final records = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _attendanceRecords = records;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendance history: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_searchQuery.isEmpty) {
      return _attendanceRecords;
    }
    return _attendanceRecords.where((record) {
      final email = record['email']?.toString().toLowerCase() ?? '';
      final status = record['status']?.toString().toLowerCase() ?? '';
      final remark = record['remark']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();

      return email.contains(query) ||
          status.contains(query) ||
          remark.contains(query);
    }).toList();
  }

  String _formatDate(dynamic date) {
    if (date is Timestamp) {
      return DateFormat('dd MMM yyyy').format(date.toDate());
    }
    if (date is DateTime) {
      return DateFormat('dd MMM yyyy').format(date);
    }
    return 'No Date';
  }

  String _formatTime(dynamic time) {
    if (time is Timestamp) {
      return DateFormat('HH:mm').format(time.toDate());
    }
    if (time is DateTime) {
      return DateFormat('HH:mm').format(time);
    }
    return '--:--';
  }

  String _formatLocation(Map<String, dynamic>? location) {
    if (location == null) return 'No location data';

    final address = location['address'] as String?;
    if (address != null && address.isNotEmpty) {
      return address;
    }

    final lat = location['latitude'] as double?;
    final lng = location['longitude'] as double?;
    if (lat != null && lng != null) {
      return 'Lat: ${lat.toStringAsFixed(6)}, Lng: ${lng.toStringAsFixed(6)}';
    }

    return 'Location data incomplete';
  }

  String _getStatusDisplay(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'late':
        return 'Late';
      case 'half-day':
        return 'Half Day';
      case 'leave':
        return 'Leave';
      default:
        return 'Unknown';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'late':
        return Colors.orange;
      case 'half-day':
        return Colors.amber;
      case 'leave':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildLocationInfo(Map<String, dynamic>? location, String title) {
    if (location == null) return const SizedBox.shrink();

    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Address: ${_formatLocation(location)}'),
              if (location['latitude'] != null && location['longitude'] != null) ...[
                const SizedBox(height: 8),
                Text('Coordinates: ${location['latitude']}, ${location['longitude']}'),
              ],
              if (location['accuracy'] != null) ...[
                const SizedBox(height: 8),
                Text('Accuracy: ${location['accuracy']} meters'),
              ],
              if (location['distance'] != null) ...[
                const SizedBox(height: 8),
                Text('Distance from office: ${location['distance'].toStringAsFixed(0)} meters'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdmin ? 'All Attendance History' : 'My Attendance History'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search by email, status, or remark',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Attendance records
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredRecords.isEmpty
                ? const Center(
              child: Text(
                'No attendance records found',
                style: TextStyle(fontSize: 16),
              ),
            )
                : ListView.builder(
              itemCount: _filteredRecords.length,
              itemBuilder: (context, index) {
                final record = _filteredRecords[index];
                final status = record['status']?.toString() ?? 'Unknown';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ExpansionTile(
                    title: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isAdmin
                                    ? (record['email'] ?? 'Unknown')
                                    : _formatDate(record['date']),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              if (widget.isAdmin)
                                Text(
                                  _formatDate(record['date']),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.login, size: 16),
                            const SizedBox(width: 4),
                            Text('In: ${_formatTime(record['checkInTime'] ?? record['checkin_time'])}'),
                            const SizedBox(width: 16),
                            const Icon(Icons.logout, size: 16),
                            const SizedBox(width: 4),
                            Text('Out: ${_formatTime(record['checkOutTime'] ?? record['checkout_time'])}'),
                          ],
                        ),
                        if (record['remark'] != null && record['remark'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Remark: ${record['remark']}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    children: [
                      // Check-in location
                      _buildLocationInfo(
                        record['checkin_location'] ?? record['checkInLocation'],
                        'Check-in Location',
                      ),

                      // Check-out location
                      _buildLocationInfo(
                        record['checkout_location'] ?? record['checkOutLocation'],
                        'Check-out Location',
                      ),

                      // Additional details
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (record['workDuration'] != null) ...[
                              Text('Work Duration: ${record['workDuration']}'),
                              const SizedBox(height: 8),
                            ],
                            if (record['markedby'] != null) ...[
                              Text('Marked by: ${record['markedby']}'),
                              const SizedBox(height: 8),
                            ],
                            if (record['createdAt'] != null) ...[
                              Text('Created: ${_formatDate(record['createdAt'])} ${_formatTime(record['createdAt'])}'),
                              const SizedBox(height: 8),
                            ],
                            if (record['updatedAt'] != null) ...[
                              Text('Last Updated: ${_formatDate(record['updatedAt'])} ${_formatTime(record['updatedAt'])}'),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchAttendanceHistory,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

// Employee Attendance History View Widget
class _EmployeeAttendanceHistoryView extends StatefulWidget {
  final String email;

  const _EmployeeAttendanceHistoryView({required this.email});

  @override
  State<_EmployeeAttendanceHistoryView> createState() => _EmployeeAttendanceHistoryViewState();
}

class _EmployeeAttendanceHistoryViewState extends State<_EmployeeAttendanceHistoryView> {
  List<Map<String, dynamic>> _attendanceHistory = [];
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchAttendanceHistory();
  }

  Future<void> _fetchAttendanceHistory() async {
    setState(() => _loading = true);

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .where('email', isEqualTo: widget.email)
          .orderBy('date', descending: true)
          .limit(100)
          .get();

      final history = <Map<String, dynamic>>[];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        history.add(data);
      }

      setState(() {
        _attendanceHistory = history;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading attendance history: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is Timestamp) {
      return DateFormat('MMM dd, yyyy').format(date.toDate());
    }
    return date.toString();
  }

  String _formatTime(dynamic time) {
    if (time == null) return '--:--';
    if (time is Timestamp) {
      return DateFormat('HH:mm').format(time.toDate());
    }
    return time.toString();
  }

  String _getStatusDisplay(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return 'Present';
      case 'absent':
        return 'Absent';
      case 'leave':
        return 'Leave';
      case 'late':
        return 'Late';
      case 'half-day':
        return 'Half Day';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'leave':
        return Colors.orange;
      case 'late':
        return Colors.amber;
      case 'half-day':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_searchQuery.isEmpty) return _attendanceHistory;

    return _attendanceHistory.where((record) {
      final date = _formatDate(record['date']).toLowerCase();
      final status = _getStatusDisplay(record['status'] ?? '').toLowerCase();
      final checkIn = _formatTime(record['checkInTime']).toLowerCase();
      final checkOut = _formatTime(record['checkOutTime']).toLowerCase();

      return date.contains(_searchQuery.toLowerCase()) ||
          status.contains(_searchQuery.toLowerCase()) ||
          checkIn.contains(_searchQuery.toLowerCase()) ||
          checkOut.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;

    return Column(
      children: [
        // Search Bar
        Padding(
          padding: EdgeInsets.all(block * 4),
          child: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: InputDecoration(
              hintText: 'Search attendance history...',
              prefixIcon: Icon(Icons.search, size: block * 5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(block * 2),
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
            ),
          ),
        ),

        // History List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filteredHistory.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history,
                  size: block * 15,
                  color: colorScheme.onSurface.withOpacity(0.5),
                ),
                SizedBox(height: block * 3),
                Text(
                  'No attendance records found',
                  style: TextStyle(
                    fontSize: 16 * fontScale,
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: block * 4),
            itemCount: _filteredHistory.length,
            itemBuilder: (context, index) {
              final record = _filteredHistory[index];
              final status = record['status'] ?? '';

              return Card(
                margin: EdgeInsets.only(bottom: block * 2),
                elevation: 2,
                child: ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(block * 1.5),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(block * 2),
                    ),
                    child: Icon(
                      _getStatusIcon(status),
                      color: _getStatusColor(status),
                      size: block * 5,
                    ),
                  ),
                  title: Text(
                    _formatDate(record['date']),
                    style: TextStyle(
                      fontSize: 16 * fontScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${_getStatusDisplay(status)}',
                        style: TextStyle(
                          fontSize: 14 * fontScale,
                          color: _getStatusColor(status),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: block * 1),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'In: ${_formatTime(record['checkInTime'])}',
                              style: TextStyle(
                                fontSize: 12 * fontScale,
                                color: Colors.green,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'Out: ${_formatTime(record['checkOutTime'])}',
                              style: TextStyle(
                                fontSize: 12 * fontScale,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (record['remark'] != null && record['remark'].toString().isNotEmpty) ...[
                        SizedBox(height: block * 1),
                        Text(
                          'Remark: ${record['remark']}',
                          style: TextStyle(
                            fontSize: 12 * fontScale,
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  onTap: () => _showRecordDetails(record),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'present':
        return Icons.check_circle;
      case 'absent':
        return Icons.cancel;
      case 'leave':
        return Icons.beach_access;
      case 'late':
        return Icons.schedule;
      case 'half-day':
        return Icons.access_time;
      default:
        return Icons.help;
    }
  }

  void _showRecordDetails(Map<String, dynamic> record) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getStatusIcon(record['status'] ?? ''),
              color: _getStatusColor(record['status'] ?? ''),
              size: block * 6,
            ),
            SizedBox(width: block * 2),
            Expanded(
              child: Text(
                _formatDate(record['date']),
                style: TextStyle(
                  fontSize: 18 * fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Status', _getStatusDisplay(record['status'] ?? ''), block, fontScale, colorScheme),
            _buildDetailRow('Check In', _formatTime(record['checkInTime']), block, fontScale, colorScheme),
            _buildDetailRow('Check Out', _formatTime(record['checkOutTime']), block, fontScale, colorScheme),
            if (record['remark'] != null && record['remark'].toString().isNotEmpty)
              _buildDetailRow('Remark', record['remark'], block, fontScale, colorScheme),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Close',
              style: TextStyle(fontSize: 14 * fontScale),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, double block, double fontScale, ColorScheme colorScheme) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: block * 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: block * 20,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14 * fontScale,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14 * fontScale,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
