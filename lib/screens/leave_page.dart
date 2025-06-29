import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LeavePage extends StatefulWidget {
  final String email;
  final String? role;
  const LeavePage({super.key, required this.email, this.role});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  String _reason = '';
  bool _isLoading = false;
  final Map<String, String> _userNames = {}; // email -> name
  bool _isAdmin = false;
  String? _selectedLeaveTypeValue1;
  List<Map<String, dynamic>> _leaveTypeCodes = [];
  final List<String> _leaveTypeDocIds = [];
  final Map<int, String> _leaveTypeDescriptions = {};
  final TextEditingController _longDescController = TextEditingController();
  final TextEditingController _shortDescController = TextEditingController();
  DateTime? _dateOfWorking;
  bool _isHalfDay = false;
  String _adminStatusFilter = 'all';

  // Fallback leave types if Firestore is empty
  final List<Map<String, dynamic>> _defaultLeaveTypes = [
    {
      'Value1': 'General Leave',
      'Name': 'General Leave',
      'Long Description': 'General Leave Description',
      'Short Description': 'GL',
    },
    {
      'Value1': 'Sick Leave',
      'Name': 'Sick Leave',
      'Long Description': 'Sick Leave Description',
      'Short Description': 'SL',
    },
    {
      'Value1': 'Casual Leave',
      'Name': 'Casual Leave',
      'Long Description': 'Casual Leave Description',
      'Short Description': 'CL',
    },
  ];

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoadNames();
    _loadLeaveTypes();
  }

  Future<void> _checkAdminAndLoadNames() async {
    if (widget.role != null) {
      setState(() => _isAdmin = widget.role!.toLowerCase() == 'admin');
    } else {
      // Fetch role from Firestore if not provided
      final userSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();
      if (userSnap.docs.isNotEmpty) {
        final role =
        userSnap.docs.first.data()['role']?.toString().toLowerCase();
        setState(() => _isAdmin = role == 'admin');
      }
    }
    // Load all user names for admin view
    if (_isAdmin) {
      final usersSnap =
      await FirebaseFirestore.instance.collection('users').get();
      for (var doc in usersSnap.docs) {
        _userNames[doc.data()['email']] = doc.data()['name'] ?? 'Unknown';
      }
    }
  }

  Future<void> _loadLeaveTypes() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('codes_master')
          .where('type', isEqualTo: 'leave type')
          .where('Active', isEqualTo: true)
          .get();

      final leaveTypes = querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      setState(() {
        _leaveTypeCodes =
        leaveTypes.isNotEmpty ? leaveTypes : _defaultLeaveTypes;
        if (_leaveTypeCodes.isNotEmpty) {
          _selectedLeaveTypeValue1 = _leaveTypeCodes[0]['Value1'];
          _longDescController.text =
              _leaveTypeCodes[0]['Long Description'] ?? '';
          _shortDescController.text =
              _leaveTypeCodes[0]['Short Description'] ?? '';
        }
      });
    } catch (e) {
      setState(() {
        _leaveTypeCodes = _defaultLeaveTypes;
        _selectedLeaveTypeValue1 = _defaultLeaveTypes[0]['Value1'];
        _longDescController.text =
            _defaultLeaveTypes[0]['Long Description'] ?? '';
        _shortDescController.text =
            _defaultLeaveTypes[0]['Short Description'] ?? '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading leave types: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }

  Future<void> _submitLeaveRequest() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both start and end dates'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedLeaveTypeValue1 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a leave type'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedLeaveTypeValue1 == 'Comp off' && _dateOfWorking == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select the date of working for Comp off'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final selectedType = _leaveTypeCodes.firstWhere(
              (type) => type['Value1'] == _selectedLeaveTypeValue1,
          orElse: () => <String, dynamic>{});
      await FirebaseFirestore.instance.collection('leaves').add({
        'leaveType': selectedType['Value1'] ?? '',
        'longDescription': selectedType['Long Description'] ?? '',
        'shortDescription': selectedType['Short Description'] ?? '',
        'startDate': _startDate,
        'endDate': _endDate,
        'reason': _reason,
        'status': 'pending',
        'appliedOn': DateTime.now(),
        'createdBy': widget.email,
        'createdOn': DateTime.now(),
        'updatedBy': widget.email,
        'updatedOn': DateTime.now(),
        'email': widget.email,
        'isHalfDay': _isHalfDay,
        if (_selectedLeaveTypeValue1 == 'Comp off' && _dateOfWorking != null)
          'dateOfWorking': _dateOfWorking,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave request submitted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _formKey.currentState!.reset();
        setState(() {
          _startDate = null;
          _endDate = null;
          _dateOfWorking = null;
          _selectedLeaveTypeValue1 =
          _leaveTypeCodes.isNotEmpty ? _leaveTypeCodes[0]['Value1'] : null;
          _longDescController.text = _leaveTypeCodes.isNotEmpty
              ? _leaveTypeCodes[0]['Long Description'] ?? ''
              : '';
          _shortDescController.text = _leaveTypeCodes.isNotEmpty
              ? _leaveTypeCodes[0]['Short Description'] ?? ''
              : '';
          _reason = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error submitting leave request: $e'),
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

  Future<Map<String, dynamic>?> _fetchUserByEmail(String email) async {
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (userSnap.docs.isNotEmpty) {
      return userSnap.docs.first.data();
    }
    return null;
  }

  Future<String> _getEmployeeName(String email) async {
    if (_userNames.containsKey(email)) return _userNames[email]!;
    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();
    if (userSnap.docs.isNotEmpty) {
      final name = userSnap.docs.first.data()['name'] ?? email;
      _userNames[email] = name;
      return name;
    }
    return email;
  }

  Widget _buildLeaveRequestForm() {
    final selectedType = _leaveTypeCodes.firstWhere(
          (code) =>
      ((code['code'] is int
          ? code['code']
          : int.tryParse(code['code']?.toString() ?? '')) ??
          -1) ==
          _selectedLeaveTypeValue1,
      orElse: () => <String, dynamic>{},
    );
    int daysSelected = 0;
    if (_startDate != null && _endDate != null) {
      daysSelected = _calculateBusinessDays(_startDate!, _endDate!);
    }
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'View Employee Leave',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              DropdownButtonFormField<String>(
                value: _selectedLeaveTypeValue1,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Leave Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _leaveTypeCodes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type['Value1'],
                    child: Text(
                      type['Value1'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedLeaveTypeValue1 = newValue;
                    final sel = _leaveTypeCodes.firstWhere(
                          (type) => type['Value1'] == newValue,
                      orElse: () => <String, dynamic>{},
                    );
                    _longDescController.text = sel['Long Description'] ?? '';
                    _shortDescController.text = sel['Short Description'] ?? '';
                    if (_selectedLeaveTypeValue1 != 'Comp off') {
                      _dateOfWorking = null;
                    }
                  });
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please select a leave type';
                  }
                  return null;
                },
              ),
              if (_selectedLeaveTypeValue1 == 'Comp off')
                Column(
                  children: [
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dateOfWorking ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _dateOfWorking = picked;
                          });
                        }
                      },
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Date of Working',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(
                            text: _dateOfWorking != null
                                ? DateFormat('yyyy-MM-dd').format(_dateOfWorking!)
                                : '',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Checkbox(
                    value: _isHalfDay,
                    onChanged: (val) {
                      setState(() {
                        _isHalfDay = val ?? false;
                      });
                    },
                  ),
                  const Text('Apply for Half Day Leave'),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shortDescController,
                decoration: const InputDecoration(
                  labelText: 'Short Description',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a short description';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onChanged: (val) => _reason = val,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a reason for leave';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectDate(context, true),
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'Start Date',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(
                            text: _startDate != null
                                ? DateFormat('MMM dd, yyyy').format(_startDate!)
                                : '',
                          ),
                          validator: (value) {
                            if (_startDate == null) {
                              return 'Please select a start date';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _selectDate(context, false),
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: const InputDecoration(
                            labelText: 'End Date',
                            border: OutlineInputBorder(),
                          ),
                          controller: TextEditingController(
                            text: _endDate != null
                                ? DateFormat('MMM dd, yyyy').format(_endDate!)
                                : '',
                          ),
                          validator: (value) {
                            if (_endDate == null) {
                              return 'Please select an end date';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_startDate != null && _endDate != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Number of days selected (excluding weekends): $daysSelected',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'No. of days leave',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: daysSelected.toString(),
                    ),
                  ],
                ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitLeaveRequest,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : const Text(
                    'Submit Leave Request',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveRequestCard(Map<String, dynamic> data) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      } else if (value is Timestamp) {
        return value.toDate();
      } else {
        return DateTime.now();
      }
    }

    final startDate = parseDate(data['startDate']);
    final endDate = parseDate(data['endDate']);
    final appliedOn = parseDate(data['appliedOn']);
    final dateOfWorking =
    data['dateOfWorking'] != null ? parseDate(data['dateOfWorking']) : null;
    final status = data['status'] as String;
    final email = data['email'] ?? '';
    final employeeName = _userNames[email] ?? email ?? 'N/A';
    final employeeEmail = email ?? 'N/A';
    final leaveTypeDesc =
        _leaveTypeDescriptions[data['leaveTypeCode'] as int? ?? -1] ??
            data['leaveType'] ??
            'Unknown';

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'approved':
        statusColor = Colors.green;
        break;
      case 'rejected':
        statusColor = Colors.red;
        break;
      default:
        statusColor = Colors.orange;
    }

    Widget approverWidget = const SizedBox.shrink();
    if (data['status'] != 'pending' && data['actionedBy'] != null) {
      return FutureBuilder<Map<String, dynamic>?>(
        future: _fetchUserByEmail(data['actionedBy']),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          leaveTypeDesc,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'From: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'To: ${DateFormat('MMM dd, yyyy').format(endDate)}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    if (dateOfWorking != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Row(
                          children: [
                            const Icon(Icons.work,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text(
                              'Date of Working: ${DateFormat('MMM dd, yyyy').format(dateOfWorking)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.note, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Reason: ${data['reason']}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time,
                            size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Applied on: ${DateFormat('MMM dd, yyyy').format(appliedOn)}',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    if (status == 'approve' && data['actionedBy'] != null)
                      Text('Approved by: ${data['actionedBy']}', style: const TextStyle(color: Colors.green)),
                    if (status == 'reject' && data['actionedBy'] != null)
                      Text('Rejected by: ${data['actionedBy']}', style: const TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            );
          }
          final user = snapshot.data;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        leaveTypeDesc,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'From: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'To: ${DateFormat('MMM dd, yyyy').format(endDate)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  if (dateOfWorking != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.work, size: 16, color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            'Date of Working: ${DateFormat('MMM dd, yyyy').format(dateOfWorking)}',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.note, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reason: ${data['reason']}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        'Applied on: ${DateFormat('MMM dd, yyyy').format(appliedOn)}',
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  if (status == 'approve' && data['actionedBy'] != null)
                    Text('Approved by: ${data['actionedBy']}', style: const TextStyle(color: Colors.green)),
                  if (status == 'reject' && data['actionedBy'] != null)
                    Text('Rejected by: ${data['actionedBy']}', style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          );
        },
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isAdmin) ...[
              FutureBuilder<String>(
                future: _getEmployeeName(employeeEmail),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? employeeEmail;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(employeeEmail, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    ],
                  );
                },
              ),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  leaveTypeDesc,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'From: ${DateFormat('MMM dd, yyyy').format(startDate)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'To: ${DateFormat('MMM dd, yyyy').format(endDate)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.note, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Reason: ${data['reason']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'Applied on: ${DateFormat('MMM dd, yyyy').format(appliedOn)}',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
            if (status == 'approve' && (data['approvalReason'] ?? '').toString().isNotEmpty)
              Text('Reason of Approve: ${data['approvalReason']}', style: const TextStyle(color: Colors.green)),
            if (status == 'approve' && (data['actionedBy'] ?? '').toString().isNotEmpty)
              Text('Approved By: ${data['actionedBy']}', style: const TextStyle(color: Colors.green)),
            if (status == 'reject' && (data['rejectionReason'] ?? '').toString().isNotEmpty)
              Text('Reason of Reject: ${data['rejectionReason']}', style: const TextStyle(color: Colors.red)),
            if (status == 'reject' && (data['actionedBy'] ?? '').toString().isNotEmpty)
              Text('Rejected By: ${data['actionedBy']}', style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;
    return Scaffold(
      appBar: AppBar(
        title: Text('Leave', style: TextStyle(fontSize: 22 * fontScale)),
        backgroundColor: const Color(0xFF1976D2),
      ),
      body: _isAdmin ? _buildAdminView(block, fontScale) : _buildEmployeeView(block, fontScale),
    );
  }

  Widget _buildAdminView(double block, double fontScale) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(block * 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text('All', style: TextStyle(fontSize: 14 * fontScale)),
                  selected: _adminStatusFilter == 'all',
                  onSelected: (_) => setState(() => _adminStatusFilter = 'all'),
                ),
                SizedBox(width: block * 2),
                ChoiceChip(
                  label: Text('Approved', style: TextStyle(fontSize: 14 * fontScale)),
                  selected: _adminStatusFilter == 'approve',
                  onSelected: (_) => setState(() => _adminStatusFilter = 'approve'),
                ),
                SizedBox(width: block * 2),
                ChoiceChip(
                  label: Text('Rejected', style: TextStyle(fontSize: 14 * fontScale)),
                  selected: _adminStatusFilter == 'reject',
                  onSelected: (_) => setState(() => _adminStatusFilter = 'reject'),
                ),
                SizedBox(width: block * 2),
                ChoiceChip(
                  label: Text('Pending', style: TextStyle(fontSize: 14 * fontScale)),
                  selected: _adminStatusFilter == 'pending',
                  onSelected: (_) => setState(() => _adminStatusFilter = 'pending'),
                ),
                SizedBox(width: block * 4),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('leaves')
                .orderBy('appliedOn', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: \\${snapshot.error}'));
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final leaves = snapshot.data?.docs ?? [];
              final filteredLeaves = leaves.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final status = (data['status'] ?? '').toString().toLowerCase();
                final statusMatch = _adminStatusFilter == 'all' ? true : status == _adminStatusFilter;
                return statusMatch;
              }).toList();
              if (filteredLeaves.isEmpty) {
                return const Center(child: Text('No leave requests found'));
              }
              return ListView.builder(
                itemCount: filteredLeaves.length,
                itemBuilder: (context, index) {
                  final leave = filteredLeaves[index].data() as Map<String, dynamic>;
                  final leaveId = filteredLeaves[index].id;
                  final status = leave['status'] as String;
                  final employeeName = _userNames[leave['email']] ?? leave['name'] ?? 'N/A';
                  final employeeEmail = leave['email'] ?? 'N/A';
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: block * 4, vertical: block * 2),
                    child: Padding(
                      padding: EdgeInsets.all(block * 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(employeeName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16 * fontScale)),
                          Text(employeeEmail, style: TextStyle(fontSize: 13 * fontScale, color: Colors.grey)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Leave Type: \\${(leave['leaveType'] ?? 'N/A').toString()}',
                                style: TextStyle(fontSize: 16 * fontScale),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: block * 3,
                                  vertical: block * 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(status).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(block * 3),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: _getStatusColor(status),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text('From: \\${leave['startDate'] != null && leave['startDate'].toString().isNotEmpty ? DateFormat('MMM dd, yyyy').format(DateTime.tryParse(leave['startDate'].toString()) ?? DateTime.now()) : 'N/A'}', style: TextStyle(fontSize: 14 * fontScale)),
                          Text('To: \\${leave['endDate'] != null && leave['endDate'].toString().isNotEmpty ? DateFormat('MMM dd, yyyy').format(DateTime.tryParse(leave['endDate'].toString()) ?? DateTime.now()) : 'N/A'}', style: TextStyle(fontSize: 14 * fontScale)),
                          if ((leave['reason'] ?? '').toString().isNotEmpty)
                            Text('Reason: \\${(leave['reason'] ?? '').toString()}', style: TextStyle(fontSize: 14 * fontScale)),
                          if (status == 'pending')
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () => _handleLeaveAction(leaveId, 'reject'),
                                    child: Text('Reject', style: TextStyle(fontSize: 14 * fontScale)),
                                  ),
                                  SizedBox(width: block * 2),
                                  ElevatedButton(
                                    onPressed: () => _handleLeaveAction(leaveId, 'approve'),
                                    child: Text('Approve', style: TextStyle(fontSize: 14 * fontScale)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeView(double block, double fontScale) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(block * 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeaveRequestForm(),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  Future<void> _handleLeaveAction(String leaveId, String action) async {
    String reason = '';
    final reasonController = TextEditingController();
    final isApprove = action == 'approve';
    final dialogResult = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isApprove ? 'Approve Leave' : 'Reject Leave'),
        content: TextField(
          controller: reasonController,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: isApprove ? 'Reason for Approval' : 'Reason for Rejection',
            hintText: isApprove ? 'Enter approval reason (optional)' : 'Enter rejection reason (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, reasonController.text.trim());
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (dialogResult == null) return;
    reason = dialogResult;
    try {
      await FirebaseFirestore.instance
          .collection('leaves')
          .doc(leaveId)
          .update({
        'status': action.toLowerCase(),
        'actionedBy': widget.email,
        'actionedOn': DateTime.now().toIso8601String(),
        if (isApprove) 'approvalReason': reason,
        if (!isApprove) 'rejectionReason': reason,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Leave request ${action.toLowerCase()}d successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error ${action.toLowerCase()}ing leave request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  int _calculateBusinessDays(DateTime start, DateTime end) {
    int days = 0;
    for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) days++;
    }
    return days;
  }
}

class EmployeeLeaveRequestsPage extends StatelessWidget {
  final String email;
  final String? role;
  const EmployeeLeaveRequestsPage({Key? key, required this.email, this.role}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Leave Requests'),
        backgroundColor: const Color(0xFF1976D2),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('leaves')
            .where('email', isEqualTo: email)
            .orderBy('appliedOn', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: \\${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final leaves = snapshot.data?.docs ?? [];
          if (leaves.isEmpty) {
            return const Center(child: Text('No leave requests found'));
          }
          return ListView.builder(
            itemCount: leaves.length,
            itemBuilder: (context, index) {
              final leave = leaves[index].data() as Map<String, dynamic>;
              // Use a local instance of _LeavePageState to access _buildLeaveRequestCard
              final tempState = _LeavePageState();
              return tempState._buildLeaveRequestCard(leave);
            },
          );
        },
      ),
    );
  }
}