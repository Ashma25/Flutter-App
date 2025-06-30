import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/dashboard_drawer.dart';

class PolicyPage extends StatefulWidget {
  final String email;
  final String? role;
  const PolicyPage({super.key, required this.email, this.role});

  @override
  State<PolicyPage> createState() => _PolicyPageState();
}

class _PolicyPageState extends State<PolicyPage> {
  String _search = '';
  List<Map<String, dynamic>> _policies = [];
  bool _isLoading = true;
  String _loadingStatus = 'Initializing...';
  bool _isAdmin = false;
  String _selectedCategory = 'All';
  final List<String> _categories = [
    'All',
    'Attendance',
    'Leave',
    'Work Hours',
    'Dress Code',
    'Security',
    'General',
    'QR Code',
    'Location',
  ];

  @override
  void initState() {
    super.initState();
    _initializePolicies();
  }

  Future<void> _initializePolicies() async {
    await _checkAdmin();
    await _createSamplePoliciesInDB();
    await _fetchPoliciesFromDB();
  }

  Future<void> _checkAdmin() async {
    if (!mounted) return;
    try {
      if (widget.role != null) {
        setState(() => _isAdmin = widget.role!.toLowerCase() == 'admin');
      } else {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: widget.email)
            .limit(1)
            .get();
        if (mounted && userSnap.docs.isNotEmpty) {
          final role = userSnap.docs.first.data()['role']?.toString().toLowerCase();
          setState(() => _isAdmin = role == 'admin');
        }
      }
    } catch (e) {
      // Handle potential error during admin check
    }
  }

  Future<void> _fetchPoliciesFromDB() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadingStatus = 'Fetching policies from database...';
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('policies')
          .orderBy('priority', descending: false)
          .get();

      final policies = snapshot.docs.map((d) {
        return {...d.data(), 'id': d.id};
      }).toList();

      if (mounted) {
        setState(() {
          _policies = policies;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        print('Error fetching policies from Firestore: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error fetching policies from Firestore: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _createSamplePoliciesInDB() async {
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadingStatus = 'Checking for existing policies...';
        });
      }
      final policiesCollection = FirebaseFirestore.instance.collection('policies');
      final existingPolicies = await policiesCollection.limit(1).get();

      if (existingPolicies.docs.isNotEmpty) {
        return;
      }

      if (mounted) {
        setState(() {
          _loadingStatus = 'No policies found. Creating samples in database...';
        });
      }

      final samplePolicies = [
        {
          'title': 'Attendance Policy',
          'description': 'Guidelines for employee attendance and time tracking',
          'content': '''
# Attendance Policy

## 1. Working Hours
- Standard working hours: 9:00 AM to 6:00 PM (Monday to Friday)
- Lunch break: 1 hour (12:00 PM to 1:00 PM)
- Flexible working hours: 8:00 AM to 7:00 PM (with prior approval)

## 2. Check-in/Check-out Requirements
- All employees must check in and check out daily using the attendance system
- Check-in must be completed within 30 minutes of arrival
- Check-out must be completed before leaving the office
- Late check-ins (after 9:15 AM) will be marked as "Late"
- Early check-outs (before 5:30 PM) require prior approval

## 3. Location Validation
- Attendance will only be recorded when employees are within the office premises
- Maximum allowed distance from office: 100 meters
- Location tracking is mandatory for attendance validation
- Employees working remotely must inform their supervisor in advance

## 4. Absence Management
- Planned absences must be requested at least 3 days in advance
- Emergency absences must be reported within 2 hours of start time
- Medical certificates required for absences longer than 3 days
- Unauthorized absences may result in disciplinary action

## 5. Consequences
- 3 consecutive late arrivals: Written warning
- 5 late arrivals in a month: Performance review
- Unauthorized absences: Disciplinary action up to termination
        ''',
          'category': 'Attendance',
          'priority': 1,
          'is_active': true,
        },
        {
          'title': 'Location-Based Attendance Policy',
          'description': 'Rules for location validation in attendance system',
          'content': '''
# Location-Based Attendance Policy

## 1. Location Tracking Requirements
- GPS location tracking is mandatory for all attendance records
- Location data is collected only during check-in and check-out
- Location accuracy must be within 10 meters of actual position
- Location data is stored securely and used only for attendance validation

## 2. Office Location Validation
- Primary office location is configured in the system
- Maximum allowed distance from office: 100 meters
- Employees must be physically present at the office for attendance
- Location validation prevents proxy attendance and ensures accountability

## 3. Remote Work Considerations
- Employees working from home must update their work location
- Remote work requires prior approval from supervisor
- Location tracking is still required for remote work attendance
- Different location validation rules may apply for remote work

## 4. Technical Requirements
- Location services must be enabled on employee devices
- Internet connection required for location validation
- GPS signal must be available for accurate location tracking
- Location permission must be granted to the attendance app

## 5. Privacy and Security
- Location data is encrypted and stored securely
- Location data is only used for attendance validation
- Location data is automatically deleted after 90 days
- Employees have the right to review their location data
        ''',
          'category': 'Location',
          'priority': 1,
          'is_active': true,
        },
        {
          'title': 'QR Code Attendance Policy',
          'description': 'Guidelines for QR code-based attendance system',
          'content': '''
# QR Code Attendance Policy

## 1. QR Code Usage
- QR codes are generated daily for attendance validation
- QR codes are valid only for the current day
- QR codes must be scanned within the office premises
- Each QR code can only be used once per employee per day

## 2. QR Code Security
- QR codes contain encrypted attendance data
- QR codes expire at the end of each working day
- Sharing QR codes with other employees is strictly prohibited
- Unauthorized QR code generation is a security violation

## 3. Scanning Requirements
- QR codes must be scanned using the official attendance app
- Camera permission is required for QR code scanning
- QR codes must be clearly visible and well-lit for scanning
- Failed scans should be reported to IT support

## 4. Backup Procedures
- Manual check-in/check-out available if QR scanning fails
- Alternative attendance methods available during system maintenance
- Emergency attendance procedures for power outages
- Contact IT support for technical issues with QR scanning

## 5. Compliance
- All employees must use QR code attendance when available
- Failure to use QR code attendance without valid reason may result in disciplinary action
- Regular audits of QR code usage will be conducted
- Violations of QR code policy will be investigated
        ''',
          'category': 'QR Code',
          'priority': 2,
          'is_active': true,
        },
        {
          'title': 'Work Hours and Overtime Policy',
          'description': 'Guidelines for working hours and overtime compensation',
          'content': '''
# Work Hours and Overtime Policy

## 1. Standard Working Hours
- Regular working hours: 40 hours per week
- Daily working hours: 8 hours (excluding lunch break)
- Work week: Monday to Friday
- Weekend work requires prior approval

## 2. Overtime Guidelines
- Overtime is work performed beyond regular working hours
- Overtime must be pre-approved by supervisor
- Overtime is compensated at 1.5x regular hourly rate
- Maximum overtime: 12 hours per week (unless emergency)

## 3. Break Times
- Lunch break: 1 hour (unpaid)
- Short breaks: 15 minutes morning and afternoon (paid)
- Break times are flexible but must be reasonable
- Breaks should not interfere with work productivity

## 4. Flexible Working Arrangements
- Flexible start times: 8:00 AM to 10:00 AM
- Flexible end times: 5:00 PM to 7:00 PM
- Core hours: 10:00 AM to 4:00 PM (all employees must be available)
- Flexible arrangements require supervisor approval

## 5. Time Tracking
- All work hours must be accurately recorded
- Time tracking includes regular hours and overtime
- Inaccurate time records may result in disciplinary action
- Regular audits of time records will be conducted
        ''',
          'category': 'Work Hours',
          'priority': 2,
          'is_active': true,
        },
        {
          'title': 'Leave Management Policy',
          'description': 'Guidelines for requesting and managing employee leave',
          'content': '''
# Leave Management Policy

## 1. Types of Leave
- Annual Leave: 20 days per year
- Sick Leave: 10 days per year
- Personal Leave: 5 days per year
- Maternity/Paternity Leave: As per legal requirements
- Bereavement Leave: 3 days for immediate family

## 2. Leave Request Process
- Leave requests must be submitted at least 3 days in advance
- Emergency leave must be reported within 2 hours
- Leave requests require supervisor approval
- Leave balance is tracked in the HR system

## 3. Leave Approval
- Annual and personal leave: Supervisor approval required
- Sick leave: Self-certification for up to 3 days
- Medical certificate required for sick leave longer than 3 days
- Leave may be denied during peak business periods

## 4. Leave Balance
- Leave balance is calculated annually
- Unused leave may be carried forward (maximum 5 days)
- Leave balance is reset on January 1st each year
- Payment for unused leave at termination (as per legal requirements)

## 5. Leave Documentation
- All leave must be properly documented
- Leave records are maintained in the HR system
- Regular audits of leave records will be conducted
- Falsification of leave records is a serious violation
        ''',
          'category': 'Leave',
          'priority': 2,
          'is_active': true,
        },
        {
          'title': 'Dress Code Policy',
          'description': 'Guidelines for appropriate workplace attire',
          'content': '''
# Dress Code Policy

## 1. General Guidelines
- Professional and business-appropriate attire required
- Clean, neat, and well-maintained clothing
- Clothing should be comfortable and suitable for work environment
- Personal hygiene and grooming standards must be maintained

## 2. Business Casual Attire
- Collared shirts, polo shirts, or blouses
- Slacks, khakis, or dress pants
- Skirts or dresses (knee-length or longer)
- Closed-toe shoes (no flip-flops or sandals)
- Jeans allowed on Fridays only

## 3. Formal Business Attire
- Required for client meetings and presentations
- Suits, blazers, or professional dresses
- Dress shirts and ties for men
- Professional footwear
- Conservative accessories

## 4. Inappropriate Attire
- Revealing or provocative clothing
- Clothing with offensive slogans or graphics
- Athletic wear (except for fitness activities)
- Beachwear or casual summer clothing
- Excessive jewelry or accessories

## 5. Special Considerations
- Safety equipment required in designated areas
- Weather-appropriate clothing allowed
- Religious or cultural attire accommodations available
- Medical accommodations for special clothing needs
        ''',
          'category': 'Dress Code',
          'priority': 3,
          'is_active': true,
        },
        {
          'title': 'Security Policy',
          'description': 'Guidelines for workplace security and access control',
          'content': '''
# Security Policy

## 1. Access Control
- Employee ID cards required for building access
- Visitors must be escorted and wear visitor badges
- After-hours access requires prior approval
- Lost or stolen ID cards must be reported immediately

## 2. Information Security
- Passwords must be strong and changed regularly
- No sharing of login credentials
- Workstations must be locked when unattended
- Sensitive information must not be left on desks

## 3. Physical Security
- Report suspicious activity to security immediately
- Secure personal belongings in lockers
- No unauthorized photography or recording
- Follow emergency evacuation procedures

## 4. Data Protection
- Company data must not be shared with unauthorized persons
- Use only approved devices for work
- Regular backups of important data
- Report data breaches immediately

## 5. Compliance
- All employees must complete security training annually
- Regular security audits will be conducted
- Violations may result in disciplinary action
- Security incidents will be investigated thoroughly
        ''',
          'category': 'Security',
          'priority': 1,
          'is_active': true,
        },
        {
          'title': 'General Workplace Policy',
          'description': 'General guidelines for workplace conduct and behavior',
          'content': '''
# General Workplace Policy

## 1. Professional Conduct
- Treat all colleagues with respect and dignity
- Maintain professional communication at all times
- No harassment, discrimination, or bullying
- Report inappropriate behavior to HR immediately

## 2. Workplace Environment
- Maintain clean and organized workspace
- Follow health and safety guidelines
- No smoking in designated non-smoking areas
- Keep noise levels appropriate for work environment

## 3. Technology Use
- Company technology for business purposes only
- No personal use during working hours
- Follow IT security guidelines
- Report technical issues to IT support

## 4. Communication
- Use appropriate communication channels
- Respond to emails and messages promptly
- Maintain confidentiality of company information
- Professional communication in all interactions

## 5. Performance Standards
- Meet assigned deadlines and quality standards
- Participate in training and development programs
- Follow company procedures and policies
- Continuous improvement and learning encouraged
        ''',
          'category': 'General',
          'priority': 3,
          'is_active': true,
        },
      ];

      final batch = FirebaseFirestore.instance.batch();
      for (final policy in samplePolicies) {
        final docRef = policiesCollection.doc();
        batch.set(docRef, {
          ...policy,
          'created_by': 'system',
          'created_at': FieldValue.serverTimestamp(),
          'updated_by': 'system',
          'updated_at': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

    } catch (e) {
      if (mounted) {
        print('Error creating sample policies in Firestore: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('FATAL: Could not create sample policies in Firestore. Check security rules. Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredPolicies {
    return _policies.where((policy) {
      final matchesCategory = _selectedCategory == 'All' ||
          policy['category'] == _selectedCategory;
      final matchesSearch = _search.isEmpty ||
          (policy['title'] ?? '').toString().toLowerCase().contains(_search.toLowerCase()) ||
          (policy['content'] ?? '').toString().toLowerCase().contains(_search.toLowerCase());

      return matchesCategory && matchesSearch;
    }).toList();
  }

  void _showPolicyDialog([Map<String, dynamic>? policy]) {
    final isEditing = policy != null;
    final TextEditingController titleController =
    TextEditingController(text: policy?['title'] ?? '');
    final TextEditingController contentController =
    TextEditingController(text: policy?['content'] ?? '');
    final TextEditingController descriptionController =
    TextEditingController(text: policy?['description'] ?? '');
    final TextEditingController priorityController =
    TextEditingController(text: (policy?['priority'] ?? 1).toString());
    String category = policy?['category'] ?? 'General';
    bool isActive = policy?['is_active'] ?? true;

    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isEditing ? 'Edit Policy' : 'Add New Policy',
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
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _categories.where((c) => c != 'All').map((c) =>
                      DropdownMenuItem(value: c, child: Text(c))
                  ).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => category = val);
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Policy Title',
                    labelStyle: TextStyle(color: colorScheme.onSurface),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.title, color: colorScheme.onSurface),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Short Description',
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
                  controller: contentController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Policy Content',
                    labelStyle: TextStyle(color: colorScheme.onSurface),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.article, color: colorScheme.onSurface),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                  ),
                  maxLines: 8,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priorityController,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: InputDecoration(
                    labelText: 'Priority (1-10)',
                    labelStyle: TextStyle(color: colorScheme.onSurface),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: Icon(Icons.priority_high, color: colorScheme.onSurface),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    // Priority will be parsed from controller value
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: SwitchListTile(
                    value: isActive,
                    onChanged: (val) => setState(() => isActive = val),
                    title: Text(
                      'Active',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    activeColor: colorScheme.primary,
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
                if (titleController.text.trim().isEmpty ||
                    contentController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Title and content are required!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final data = {
                  'title': titleController.text.trim(),
                  'content': contentController.text.trim(),
                  'description': descriptionController.text.trim(),
                  'category': category,
                  'priority': int.tryParse(priorityController.text) ?? 1,
                  'is_active': isActive,
                  'updated_by': widget.email,
                  'updated_at': FieldValue.serverTimestamp(),
                };

                try {
                  if (isEditing) {
                    await FirebaseFirestore.instance
                        .collection('policies')
                        .doc(policy['id'])
                        .update(data);
                  } else {
                    data['created_by'] = widget.email;
                    data['created_at'] = FieldValue.serverTimestamp();
                    await FirebaseFirestore.instance
                        .collection('policies')
                        .add(data);
                  }

                  Navigator.pop(context);
                  _fetchPoliciesFromDB(); // Refresh from DB
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Policy ${isEditing ? 'updated' : 'added'} successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Database Error: $e'),
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

  void _showPolicyDetails(Map<String, dynamic> policy) {
    showDialog(
      context: context,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            policy['title'] ?? 'Policy Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (policy['description'] != null && policy['description'].toString().isNotEmpty) ...[
                  Text(
                    'Description:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    policy['description'],
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Content:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  policy['content'] ?? '',
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Category: ${policy['category'] ?? 'General'}',
                        style: TextStyle(
                          color: colorScheme.onPrimaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Priority: ${policy['priority'] ?? 1}',
                        style: TextStyle(
                          color: colorScheme.onSecondaryContainer,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (policy['is_active'] ?? true) ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    (policy['is_active'] ?? true) ? 'Active' : 'Inactive',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (_isAdmin) ...[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showPolicyDialog(policy);
                },
                child: Text(
                  'Edit',
                  style: TextStyle(color: colorScheme.primary),
                ),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Close',
                style: TextStyle(color: colorScheme.onSurface),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final block = width / 100;
    final fontScale = width < 400 ? 0.85 : width < 600 ? 0.95 : 1.0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Policy', style: TextStyle(fontSize: 22 * fontScale)),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      drawer: DashboardDrawer(
        onThemeChanged: () {
          setState(() {});
        },
        userEmail: widget.email,
      ),
      body: Padding(
        padding: EdgeInsets.all(block * 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: block * 4),
            Text('Policies', style: TextStyle(fontSize: 18 * fontScale, fontWeight: FontWeight.bold)),
            // Search and filter section
            Container(
              padding: const EdgeInsets.all(16),
              color: colorScheme.surfaceContainerHighest,
              child: Column(
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 280, // Fixed width for search box
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search policies...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: colorScheme.surface,
                            ),
                            onChanged: (value) {
                              setState(() {
                                _search = value;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 180, // Fixed width for dropdown
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _selectedCategory,
                            items: _categories.map((category) =>
                                DropdownMenuItem(value: category, child: Text(category))
                            ).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCategory = value!;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Policies list
            Expanded(
              child: _isLoading
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(_loadingStatus),
                  ],
                ),
              )
                  : _filteredPolicies.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.policy,
                      size: 64,
                      color: colorScheme.onSurface.withOpacity(0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No policies found',
                      style: TextStyle(
                        fontSize: 18,
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredPolicies.length,
                itemBuilder: (context, index) {
                  final policy = _filteredPolicies[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.policy,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        policy['title'] ?? 'Untitled Policy',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (policy['description'] != null &&
                              policy['description'].toString().isNotEmpty)
                            Text(
                              policy['description'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    policy['category'] ?? 'General',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Priority: ${policy['priority'] ?? 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (policy['is_active'] ?? true) ? Colors.green : Colors.red,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    (policy['is_active'] ?? true) ? 'Active' : 'Inactive',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showPolicyDetails(policy),
                      trailing: _isAdmin
                          ? PopupMenuButton(
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                        onSelected: (value) async {
                          if (value == 'edit') {
                            _showPolicyDialog(policy);
                          } else if (value == 'delete') {
                            // Show confirmation dialog
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Confirm Delete'),
                                content: const Text('Are you sure you want to delete this policy?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirmed == true) {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('policies')
                                    .doc(policy['id'])
                                    .delete();
                                _fetchPoliciesFromDB();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Policy deleted successfully!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Error deleting policy: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          }
                        },
                      )
                          : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isAdmin
          ? FloatingActionButton(
        onPressed: () => _showPolicyDialog(),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        child: const Icon(Icons.add),
      )
          : null,
    );
  }
}