import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ApplyLeavePage extends StatefulWidget {
  final String email;
  const ApplyLeavePage({Key? key, required this.email}) : super(key: key);

  @override
  State<ApplyLeavePage> createState() => _ApplyLeavePageState();
}

class _ApplyLeavePageState extends State<ApplyLeavePage> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _startDate;
  DateTime? _endDate;
  String _reason = '';
  bool _isLoading = false;
  String? _selectedLeaveTypeValue1;
  List<Map<String, dynamic>> _leaveTypeCodes = [];
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
  final TextEditingController _shortDescController = TextEditingController();
  DateTime? _dateOfWorking;

  @override
  void initState() {
    super.initState();
    _loadLeaveTypes();
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
        _leaveTypeCodes = leaveTypes.isNotEmpty ? leaveTypes : _defaultLeaveTypes;
        if (_leaveTypeCodes.isNotEmpty) {
          _selectedLeaveTypeValue1 = _leaveTypeCodes[0]['Value1'];
          _shortDescController.text = _leaveTypeCodes[0]['Short Description'] ?? '';
        }
      });
    } catch (e) {
      setState(() {
        _leaveTypeCodes = _defaultLeaveTypes;
        _selectedLeaveTypeValue1 = _defaultLeaveTypes[0]['Value1'];
        _shortDescController.text = _defaultLeaveTypes[0]['Short Description'] ?? '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading leave types: $e'), backgroundColor: Colors.red),
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
        const SnackBar(content: Text('Please select both start and end dates'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedLeaveTypeValue1 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a leave type'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_selectedLeaveTypeValue1 == 'Comp off' && _dateOfWorking == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the date of working for Comp off'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final selectedType = _leaveTypeCodes.firstWhere(
            (type) => type['Value1'] == _selectedLeaveTypeValue1,
        orElse: () => <String, dynamic>{},
      );
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
        if (_selectedLeaveTypeValue1 == 'Comp off' && _dateOfWorking != null)
          'dateOfWorking': _dateOfWorking,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave request submitted successfully'), backgroundColor: Colors.green),
        );
        _formKey.currentState!.reset();
        setState(() {
          _startDate = null;
          _endDate = null;
          _dateOfWorking = null;
          _selectedLeaveTypeValue1 = _leaveTypeCodes.isNotEmpty ? _leaveTypeCodes[0]['Value1'] : null;
          _shortDescController.text = _leaveTypeCodes.isNotEmpty ? _leaveTypeCodes[0]['Short Description'] ?? '' : '';
          _reason = '';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting leave request: $e'), backgroundColor: Colors.red),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Apply Leave')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                            prefixIcon: Icon(Icons.work),
                          ),
                          controller: TextEditingController(
                            text: _dateOfWorking != null
                                ? DateFormat('MMM dd, yyyy').format(_dateOfWorking!)
                                : '',
                          ),
                          validator: (value) {
                            if (_selectedLeaveTypeValue1 == 'Comp off' && _dateOfWorking == null) {
                              return 'Please select the date of working';
                            }
                            return null;
                          },
                        ),
                      ),
                    ),
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
                    child: TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Start Date',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.calendar_today),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: () => _selectDate(context, true),
                        ),
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
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'End Date',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.calendar_today),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month),
                          onPressed: () => _selectDate(context, false),
                        ),
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
}// TODO Implement this library.