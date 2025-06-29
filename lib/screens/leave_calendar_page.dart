import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/dashboard_drawer.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';


extension StringCasingExtension on String {
    String capitalize() {
        return isNotEmpty
            ? this[0].toUpperCase() + substring(1).toLowerCase()
            : this;
    }
}

class LeaveCalendarPage extends StatefulWidget {
    final String? userRole;
    final String userEmail;

    const LeaveCalendarPage({
        Key? key,
        this.userRole,
        required this.userEmail,
    }) : super(key: key);

    @override
    State<LeaveCalendarPage> createState() => _LeaveCalendarPageState();
}

class _LeaveCalendarPageState extends State<LeaveCalendarPage> {
    CalendarFormat _calendarFormat = CalendarFormat.month;
    DateTime _focusedDay = DateTime.now();
    DateTime? _selectedDay;
    Map<DateTime, List<Map<String, dynamic>>> _holidays = {};
    Map<DateTime, List<Map<String, dynamic>>> _events = {};
    bool _isLoading = true;
    int _totalHolidays = 0;
    bool _isAdmin = false;
    String _filterType = 'all'; // 'all', 'holidays', 'leaves'
    final Map<String, Color> _statusColors = {
        'approved': Colors.green,
        'pending': Colors.orange,
        'rejected': Colors.red,
    };

    // Theme-aware colors
    Color get _holidayColor => Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF64B5F6) // Light blue for dark theme
        : const Color(0xFF1976D2); // Dark blue for light theme

    Color get _leaveColor => Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF81C784) // Light green for dark theme
        : const Color(0xFF4CAF50); // Dark green for light theme

    @override
    void initState() {
        super.initState();
        _loadUserRole();
        _loadEvents();
    }

    Future<void> _loadUserRole() async {
        try {
            final snapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: widget.userEmail)
                .limit(1)
                .get();

            if (snapshot.docs.isNotEmpty) {
                final userData = snapshot.docs.first.data();
                final role = userData['role']?.toString().toLowerCase();
                setState(() {
                    _isAdmin = role == 'admin';
                    print('User role loaded: $role, isAdmin: $_isAdmin'); // Debug print
                });
            }
        } catch (e) {
            print('Error loading user role: $e');
        }
    }

    Future<void> _loadEvents() async {
        setState(() => _isLoading = true);
        try {
            // Load company holidays
            final holidaysSnapshot = await FirebaseFirestore.instance
                .collection('Leave Calendar')
                .where('Active', isEqualTo: 'Yes')
                .get();

            final Map<DateTime, List<Map<String, dynamic>>> events = {};
            final Map<DateTime, List<Map<String, dynamic>>> holidays = {};

            // Process company holidays
            for (var doc in holidaysSnapshot.docs) {
                final data = doc.data();
                DateTime holidayDate;
                if (data['holidayDate'] is Timestamp) {
                    holidayDate = (data['holidayDate'] as Timestamp).toDate();
                } else if (data['holidayDate'] is String) {
                    holidayDate = DateTime.tryParse(data['holidayDate'] as String) ?? DateTime.now();
                } else {
                    continue;
                }
                final date = DateTime(holidayDate.year, holidayDate.month, holidayDate.day);

                if (!events.containsKey(date)) {
                    events[date] = [];
                }
                if (!holidays.containsKey(date)) {
                    holidays[date] = [];
                }

                final holidayData = {
                    'type': 'company_holiday',
                    'id': doc.id,
                    'name': data['holidayName'],
                    'holidayName': data['holidayName'],
                    'holidayDate': data['holidayDate'],
                    'createdBy': data['createdBy'],
                    'createdAt': data['createdAt'],
                    'updatedBy': data['updatedBy'],
                    'updatedAt': data['updatedAt'],
                    'color': _holidayColor,
                    'description': 'Company Holiday',
                };

                events[date]!.add(holidayData);
                holidays[date]!.add(holidayData);
            }

            // Load leaves
            final leavesSnapshot = await FirebaseFirestore.instance
                .collection('leaves')
                .get();

            final Map<String, Set<DateTime>> employeeLeaveDates = {}; // Track employee leave dates

            // Get all employee names in one query
            final employeeEmails = leavesSnapshot.docs.map((doc) => doc.data()['email'] as String).toSet();
            final usersSnapshot = await FirebaseFirestore.instance
                .collection('users')
                .where('email', whereIn: employeeEmails.toList())
                .get();

            final employeeNames = {
                for (var doc in usersSnapshot.docs)
                    doc.data()['email'] as String: doc.data()['name'] as String
            };

            // Process employee leaves
            for (var doc in leavesSnapshot.docs) {
                final data = doc.data();
                final status = (data['status'] as String? ?? '').toLowerCase();

                // Only process approved leaves
                if (status != 'approved' && status != 'approve') continue;

                final startDate = (data['startDate'] is Timestamp)
                    ? (data['startDate'] as Timestamp).toDate()
                    : DateTime.tryParse(data['startDate'].toString()) ?? DateTime.now();
                final endDate = (data['endDate'] is Timestamp)
                    ? (data['endDate'] as Timestamp).toDate()
                    : DateTime.tryParse(data['endDate'].toString()) ?? DateTime.now();
                final email = data['email'] as String;
                final leaveType = data['leaveType'] as String? ?? 'Leave';
                final reason = data['reason'] as String?;
                final employeeName = employeeNames[email] ?? email;

                // Initialize employee's leave dates set if not exists
                employeeLeaveDates[email] = employeeLeaveDates[email] ?? {};

                // Add leave for each day in the range
                for (var date = startDate;
                date.isBefore(endDate.add(const Duration(days: 1)));
                date = date.add(const Duration(days: 1))) {
                    final normalizedDate = DateTime(date.year, date.month, date.day);

                    // Skip if employee already has a leave on this date
                    if (employeeLeaveDates[email]!.contains(normalizedDate)) {
                        continue;
                    }

                    employeeLeaveDates[email]!.add(normalizedDate);

                    if (!events.containsKey(normalizedDate)) {
                        events[normalizedDate] = [];
                    }
                    events[normalizedDate]!.add({
                        'type': 'leave',
                        'name': leaveType,
                        'email': email,
                        'employeeName': employeeName,
                        'reason': reason,
                        'startDate': startDate,
                        'endDate': endDate,
                        'color': _leaveColor,
                        'description': 'Employee Leave',
                        'status': status,
                    });
                }
            }

            setState(() {
                _events = events;
                _holidays = holidays;
                _totalHolidays = _holidays.length;
                _isLoading = false;
            });
        } catch (e) {
            setState(() => _isLoading = false);
            if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Error loading events: $e'),
                        backgroundColor: Colors.red,
                    ),
                );
            }
        }
    }

    List<Map<String, dynamic>> _getFilteredEvents(DateTime day) {
        final events = _events[DateTime(day.year, day.month, day.day)] ?? [];
        if (_filterType == 'holidays') {
            return events.where((e) => e['type'] == 'company_holiday').toList();
        } else if (_filterType == 'leaves') {
            return events.where((e) => e['type'] == 'leave').toList();
        }
        return events;
    }

    String _getEventTooltip(List<Map<String, dynamic>> events) {
        final holidays = events.where((e) => e['type'] == 'company_holiday').toList();
        final leaves = events.where((e) => e['type'] == 'leave').toList();

        final List<String> tooltipLines = [];

        if (holidays.isNotEmpty) {
            tooltipLines.add('Holiday: ${holidays.first['name']}');
        }

        if (leaves.isNotEmpty) {
            tooltipLines.add('Leaves:');
            for (var leave in leaves) {
                final startDate = leave['startDate'] as DateTime;
                final endDate = leave['endDate'] as DateTime;
                final duration = endDate.difference(startDate).inDays + 1;
                tooltipLines.add('• ${leave['employeeName']} - ${leave['name']} ($duration days)');
            }
        }

        return tooltipLines.join('\n');
    }

    @override
    Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        return Scaffold(
            appBar: AppBar(
                title: const Text('Leave Calendar'),
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
            ),
            backgroundColor: colorScheme.surface,
            body: _isLoading
                ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
                : SingleChildScrollView(
                child: Column(
                    children: [
                        // Calendar Card
                        Card(
                            elevation: 4,
                            margin: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    children: [
                                        TableCalendar(
                                            firstDay: DateTime.utc(2020, 1, 1),
                                            lastDay: DateTime.utc(2030, 12, 31),
                                            focusedDay: _focusedDay,
                                            calendarFormat: _calendarFormat,
                                            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                                            onDaySelected: (selectedDay, focusedDay) {
                                                setState(() {
                                                    _selectedDay = selectedDay;
                                                    _focusedDay = focusedDay;
                                                });
                                                _showDayEvents(selectedDay);
                                            },
                                            onFormatChanged: (format) {
                                                setState(() {
                                                    _calendarFormat = format;
                                                });
                                            },
                                            onPageChanged: (focusedDay) {
                                                _focusedDay = focusedDay;
                                            },
                                            calendarStyle: CalendarStyle(
                                                markersMaxCount: 2,
                                                outsideDaysVisible: false,
                                                weekendTextStyle: const TextStyle(color: Colors.red),
                                                defaultTextStyle: const TextStyle(fontSize: 14),
                                                selectedTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
                                                todayTextStyle: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                                selectedDecoration: BoxDecoration(
                                                    color: colorScheme.primary,
                                                    shape: BoxShape.circle,
                                                ),
                                                todayDecoration: BoxDecoration(
                                                    color: colorScheme.secondary,
                                                    shape: BoxShape.circle,
                                                ),
                                                weekendDecoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                ),
                                            ),
                                            calendarBuilders: CalendarBuilders(
                                                markerBuilder: (context, date, events) {
                                                    final filteredEvents = _getFilteredEvents(date);
                                                    if (filteredEvents.isEmpty) return null;

                                                    final hasHoliday = filteredEvents.any((e) => e['type'] == 'company_holiday');
                                                    final hasLeave = filteredEvents.any((e) => e['type'] == 'leave');

                                                    return Tooltip(
                                                        message: _getEventTooltip(filteredEvents),
                                                        child: Row(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                                if (hasHoliday)
                                                                    Icon(Icons.event, size: 12, color: _holidayColor),
                                                                if (hasLeave)
                                                                    Icon(Icons.person, size: 12, color: _leaveColor),
                                                            ],
                                                        ),
                                                    );
                                                },
                                                defaultBuilder: (context, date, _) {
                                                    final filteredEvents = _getFilteredEvents(date);
                                                    final holiday = filteredEvents.firstWhere(
                                                            (e) => e['type'] == 'company_holiday',
                                                        orElse: () => {},
                                                    );
                                                    final leaves = filteredEvents.where((e) => e['type'] == 'leave').toList();

                                                    // Check if it's weekend
                                                    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

                                                    return Container(
                                                        margin: const EdgeInsets.all(1),
                                                        child: Column(
                                                            mainAxisAlignment: MainAxisAlignment.center,
                                                            children: [
                                                                Text(
                                                                    '${date.day}',
                                                                    style: TextStyle(
                                                                        fontWeight: FontWeight.bold,
                                                                        fontSize: 12,
                                                                        color: isWeekend ? Colors.red : null,
                                                                    ),
                                                                ),
                                                                if (holiday.isNotEmpty)
                                                                    Container(
                                                                        margin: const EdgeInsets.only(top: 1.0),
                                                                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                        decoration: BoxDecoration(
                                                                            color: _holidayColor.withOpacity(0.1),
                                                                            borderRadius: BorderRadius.circular(4),
                                                                        ),
                                                                        child: Text(
                                                                            holiday['name'] ?? holiday['holidayName'] ?? '',
                                                                            style: TextStyle(
                                                                                fontSize: 8,
                                                                                color: _holidayColor,
                                                                                fontWeight: FontWeight.w500,
                                                                            ),
                                                                            textAlign: TextAlign.center,
                                                                            overflow: TextOverflow.ellipsis,
                                                                            maxLines: 1,
                                                                        ),
                                                                    ),
                                                                if (leaves.isNotEmpty)
                                                                    Container(
                                                                        margin: const EdgeInsets.only(top: 1.0),
                                                                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                                                        decoration: BoxDecoration(
                                                                            color: _leaveColor.withOpacity(0.1),
                                                                            borderRadius: BorderRadius.circular(4),
                                                                        ),
                                                                        child: Column(
                                                                            children: leaves.take(2).map((leave) {
                                                                                final employeeName = leave['employeeName'] as String? ?? '';
                                                                                final firstName = employeeName.split(' ').first;
                                                                                final leaveType = leave['name'] as String? ?? '';
                                                                                final description = leave['reason'] as String? ?? '';

                                                                                return Text(
                                                                                    '$firstName - ${description.isNotEmpty ? description : leaveType}',
                                                                                    style: TextStyle(
                                                                                        fontSize: 7,
                                                                                        color: _leaveColor,
                                                                                        fontWeight: FontWeight.w500,
                                                                                    ),
                                                                                    textAlign: TextAlign.center,
                                                                                    overflow: TextOverflow.ellipsis,
                                                                                    maxLines: 1,
                                                                                );
                                                                            }).toList(),
                                                                        ),
                                                                    ),
                                                            ],
                                                        ),
                                                    );
                                                },
                                            ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Filter Chips
                                        Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            alignment: WrapAlignment.center,
                                            children: [
                                                FilterChip(
                                                    label: const Text('All'),
                                                    selected: _filterType == 'all',
                                                    selectedColor: colorScheme.primary.withOpacity(0.2),
                                                    checkmarkColor: colorScheme.primary,
                                                    onSelected: (selected) {
                                                        setState(() {
                                                            _filterType = 'all';
                                                        });
                                                    },
                                                ),
                                                FilterChip(
                                                    label: const Text('Holidays'),
                                                    selected: _filterType == 'holidays',
                                                    selectedColor: _holidayColor.withOpacity(0.2),
                                                    checkmarkColor: _holidayColor,
                                                    onSelected: (selected) {
                                                        setState(() {
                                                            _filterType = 'holidays';
                                                        });
                                                    },
                                                ),
                                                FilterChip(
                                                    label: const Text('Leaves'),
                                                    selected: _filterType == 'leaves',
                                                    selectedColor: _leaveColor.withOpacity(0.2),
                                                    checkmarkColor: _leaveColor,
                                                    onSelected: (selected) {
                                                        setState(() {
                                                            _filterType = 'leaves';
                                                        });
                                                    },
                                                ),
                                            ],
                                        ),
                                        const SizedBox(height: 16),
                                        // Legend
                                        Wrap(
                                            spacing: 16,
                                            runSpacing: 8,
                                            alignment: WrapAlignment.center,
                                            children: [
                                                Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                        Icon(Icons.event, size: 16, color: _holidayColor),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                            'Holiday',
                                                            style: TextStyle(
                                                                fontSize: 12,
                                                                color: colorScheme.onSurface,
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                                Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                        Icon(Icons.person, size: 16, color: _leaveColor),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                            'Leave',
                                                            style: TextStyle(
                                                                fontSize: 12,
                                                                color: colorScheme.onSurface,
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                            ],
                                        ),
                                    ],
                                ),
                            ),
                        ),
                        // Holidays Section (scrollable, all holidays for the month)
                        if (_filterType != 'leaves')
                            Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                        Text(
                                            'Upcoming Holidays',
                                            style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: colorScheme.onSurface,
                                            ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                            height: 200,
                                            child: ListView(
                                                children: _holidays.entries
                                                    .where((entry) => entry.key.month == _focusedDay.month && entry.key.year == _focusedDay.year)
                                                    .expand((entry) => entry.value.where((e) => e['type'] == 'company_holiday').map((holiday) => Card(
                                                    margin: const EdgeInsets.only(bottom: 8),
                                                    color: Theme.of(context).brightness == Brightness.dark
                                                        ? colorScheme.surfaceContainerHighest
                                                        : colorScheme.surface,
                                                    elevation: 2,
                                                    shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        side: BorderSide(
                                                            color: _holidayColor.withOpacity(0.3),
                                                            width: 1,
                                                        ),
                                                    ),
                                                    child: ListTile(
                                                        leading: Icon(Icons.event, color: _holidayColor),
                                                        title: Text(
                                                            holiday['name'] ?? holiday['holidayName'],
                                                            style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                color: colorScheme.onSurface,
                                                            ),
                                                        ),
                                                        subtitle: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                                Text(
                                                                    'Date: ${DateFormat('MMM dd, yyyy').format((holiday['holidayDate'] as Timestamp).toDate())}',
                                                                    style: TextStyle(
                                                                        color: colorScheme.onSurface.withOpacity(0.7),
                                                                    ),
                                                                ),
                                                                Container(
                                                                    margin: const EdgeInsets.only(top: 4),
                                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                                    decoration: BoxDecoration(
                                                                        color: _holidayColor.withOpacity(0.1),
                                                                        borderRadius: BorderRadius.circular(4),
                                                                    ),
                                                                    child: Text(
                                                                        'Company Holiday',
                                                                        style: TextStyle(
                                                                            fontSize: 12,
                                                                            color: _holidayColor,
                                                                            fontWeight: FontWeight.w500,
                                                                        ),
                                                                    ),
                                                                ),
                                                            ],
                                                        ),
                                                        trailing: widget.userRole?.toLowerCase() == 'admin'
                                                            ? Row(
                                                            mainAxisSize: MainAxisSize.min,
                                                            children: [
                                                                IconButton(
                                                                    icon: Icon(Icons.edit, color: _holidayColor),
                                                                    onPressed: () => _editHoliday(holiday),
                                                                    tooltip: 'Edit Holiday',
                                                                ),
                                                                IconButton(
                                                                    icon: Icon(Icons.delete, color: colorScheme.error),
                                                                    onPressed: () => _deleteHoliday(holiday['id']),
                                                                    tooltip: 'Delete Holiday',
                                                                ),
                                                            ],
                                                        )
                                                            : null,
                                                    ),
                                                )))
                                                    .toList(),
                                            ),
                                        ),
                                    ],
                                ),
                            ),
                    ],
                ),
            ),
            floatingActionButton: FloatingActionButton(
                onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => HolidayPrintScreen(holidays: _holidays)),
                    );
                },
                tooltip: 'View & Export Holiday List',
                child: const Icon(Icons.print),
            ),
        );
    }

    Widget _buildLegendItem(String label, Color color, IconData icon) {
        final colorScheme = Theme.of(context).colorScheme;
        return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                    label,
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface,
                    ),
                ),
            ],
        );
    }

    Future<void> _showAddHolidayDialog() async {
        final TextEditingController nameController = TextEditingController();
        DateTime selectedDate = _selectedDay ?? DateTime.now();

        await showDialog(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Add Holiday'),
                content: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.9,
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                        labelText: 'Holiday Name',
                                        hintText: 'Enter holiday name',
                                    ),
                                ),
                                const SizedBox(height: 16),
                                ListTile(
                                    title: const Text('Date'),
                                    subtitle: Text(DateFormat('yyyy-MM-dd').format(selectedDate)),
                                    trailing: const Icon(Icons.calendar_today),
                                    onTap: () async {
                                        final date = await showDatePicker(
                                            context: context,
                                            initialDate: selectedDate,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                        );
                                        if (date != null) {
                                            setState(() => selectedDate = date);
                                        }
                                    },
                                ),
                            ],
                        ),
                    ),
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                        onPressed: () async {
                            if (nameController.text.isNotEmpty) {
                                try {
                                    await FirebaseFirestore.instance
                                        .collection('Leave Calendar')
                                        .add({
                                        'holidayName': nameController.text,
                                        'holidayDate': Timestamp.fromDate(selectedDate),
                                        'createdBy': widget.userEmail,
                                        'createdOn': FieldValue.serverTimestamp(),
                                        'updatedBy': widget.userEmail,
                                        'updatedOn': FieldValue.serverTimestamp(),
                                        'Active': 'Yes',
                                    });

                                    if (mounted) {
                                        Navigator.pop(context);
                                        _loadEvents();
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                                content: Text('Holiday added successfully'),
                                                backgroundColor: Colors.green,
                                            ),
                                        );
                                    }
                                } catch (e) {
                                    if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                                content: Text('Error adding holiday: $e'),
                                                backgroundColor: Colors.red,
                                            ),
                                        );
                                    }
                                }
                            }
                        },
                        child: const Text('Add'),
                    ),
                ],
            ),
        );
    }

    Future<void> _deleteHoliday(String holidayId) async {
        final bool? confirm = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) {
                return AlertDialog(
                    title: const Text('Delete Holiday'),
                    content: const Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text('Are you sure you want to delete this holiday?'),
                            SizedBox(height: 8),
                            Text(
                                'This action cannot be undone.',
                                style: TextStyle(
                                    color: Colors.red,
                                    fontStyle: FontStyle.italic,
                                ),
                            ),
                        ],
                    ),
                    actions: <Widget>[
                        TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                        ),
                        ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                            ),
                            child: const Text('Delete'),
                        ),
                    ],
                );
            },
        );

        if (confirm == true) {
            try {
                await FirebaseFirestore.instance
                    .collection('Leave Calendar')
                    .doc(holidayId)
                    .update({
                    'Active': 'No',
                    'updatedBy': widget.userEmail,
                    'updatedOn': FieldValue.serverTimestamp(),
                });

                if (mounted) {
                    _loadEvents();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Holiday deleted successfully'),
                            backgroundColor: Colors.green,
                        ),
                    );
                }
            } catch (e) {
                if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Error deleting holiday: $e'),
                            backgroundColor: Colors.red,
                        ),
                    );
                }
            }
        }
    }

    void _showDayEvents(DateTime day) {
        final colorScheme = Theme.of(context).colorScheme;
        final events = _getFilteredEvents(day);
        if (events.isEmpty) {
            // Show add holiday button even when there are no events (for admin)
            if (_isAdmin) {
                showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                        title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                                Text(DateFormat('MMMM dd, yyyy').format(day)),
                                IconButton(
                                    icon: Icon(Icons.add_circle_outline, color: _holidayColor),
                                    onPressed: () {
                                        Navigator.pop(context);
                                        _addHoliday(day);
                                    },
                                    tooltip: 'Add Holiday',
                                ),
                            ],
                        ),
                        content: const Text('No events for this date. Click the + button to add a holiday.'),
                        actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                            ),
                        ],
                    ),
                );
            }
            return;
        }

        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                        Text(DateFormat('MMMM dd, yyyy').format(day)),
                        if (_isAdmin)
                            IconButton(
                                icon: Icon(Icons.add_circle_outline, color: _holidayColor),
                                onPressed: () {
                                    Navigator.pop(context);
                                    _addHoliday(day);
                                },
                                tooltip: 'Add Holiday',
                            ),
                    ],
                ),
                content: SizedBox(
                    width: double.maxFinite,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            // Holidays section
                            if (events.any((e) => e['type'] == 'company_holiday')) ...[
                                Text(
                                    'Holidays',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _holidayColor,
                                    ),
                                ),
                                const SizedBox(height: 8),
                                ...events
                                    .where((e) => e['type'] == 'company_holiday')
                                    .map((holiday) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: colorScheme.surface,
                                    child: Padding(
                                        padding: const EdgeInsets.all(12.0),
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                                Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                        Expanded(
                                                            child: Row(
                                                                children: [
                                                                    Icon(Icons.event, color: _holidayColor, size: 24),
                                                                    const SizedBox(width: 12),
                                                                    Expanded(
                                                                        child: Text(
                                                                            holiday['name'],
                                                                            style: TextStyle(
                                                                                fontWeight: FontWeight.bold,
                                                                                fontSize: 16,
                                                                                color: colorScheme.onSurface,
                                                                            ),
                                                                        ),
                                                                    ),
                                                                ],
                                                            ),
                                                        ),
                                                        if (_isAdmin)
                                                            Row(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                    IconButton(
                                                                        icon: Icon(Icons.edit, color: _holidayColor, size: 24),
                                                                        onPressed: () {
                                                                            Navigator.pop(context);
                                                                            _editHoliday(holiday);
                                                                        },
                                                                        tooltip: 'Edit Holiday',
                                                                    ),
                                                                    IconButton(
                                                                        icon: Icon(Icons.delete, color: colorScheme.error, size: 24),
                                                                        onPressed: () {
                                                                            Navigator.pop(context);
                                                                            _deleteHoliday(holiday['id']);
                                                                        },
                                                                        tooltip: 'Delete Holiday',
                                                                    ),
                                                                ],
                                                            ),
                                                    ],
                                                ),
                                                const SizedBox(height: 8),
                                                Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                        color: _holidayColor.withOpacity(0.1),
                                                        borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(
                                                        'Company Holiday',
                                                        style: TextStyle(
                                                            color: _holidayColor,
                                                            fontWeight: FontWeight.w500,
                                                        ),
                                                    ),
                                                ),
                                                if (holiday['createdBy'] != null)
                                                    Row(
                                                        children: [
                                                            const Icon(Icons.person, size: 16, color: Colors.grey),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                                child: Text(
                                                                    'Created by: ${holiday['createdBy']}',
                                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                                    overflow: TextOverflow.ellipsis,
                                                                ),
                                                            ),
                                                        ],
                                                    ),
                                                if (holiday['updatedBy'] != null)
                                                    Row(
                                                        children: [
                                                            const Icon(Icons.update, size: 16, color: Colors.grey),
                                                            const SizedBox(width: 4),
                                                            Expanded(
                                                                child: Text(
                                                                    'Last updated by: ${holiday['updatedBy']}',
                                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                                    overflow: TextOverflow.ellipsis,
                                                                ),
                                                            ),
                                                        ],
                                                    ),
                                            ],
                                        ),
                                    ),
                                ))
                                    .toList(),
                                const Divider(),
                            ],
                            // Leaves section
                            if (events.any((e) => e['type'] == 'leave')) ...[
                                Text(
                                    'Leaves',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _leaveColor,
                                    ),
                                ),
                                const SizedBox(height: 8),
                                ...events
                                    .where((e) => e['type'] == 'leave')
                                    .map((leave) => Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    color: colorScheme.surface,
                                    child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                                Row(
                                                    children: [
                                                        Icon(Icons.person, color: _leaveColor),
                                                        const SizedBox(width: 8),
                                                        Expanded(
                                                            child: Text(
                                                                leave['employeeName'],
                                                                style: TextStyle(
                                                                    fontWeight: FontWeight.bold,
                                                                    fontSize: 16,
                                                                    color: colorScheme.onSurface,
                                                                ),
                                                            ),
                                                        ),
                                                    ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                    'Type: ${leave['name']}',
                                                    style: TextStyle(color: colorScheme.onSurface),
                                                ),
                                                Text(
                                                    'Duration: ${DateFormat('MMM dd').format(leave['startDate'])} - ${DateFormat('MMM dd, yyyy').format(leave['endDate'])}',
                                                    style: TextStyle(color: colorScheme.onSurface),
                                                ),
                                                if (leave['reason'] != null && leave['reason'].toString().isNotEmpty)
                                                    Text(
                                                        'Reason: ${leave['reason']}',
                                                        style: TextStyle(color: colorScheme.onSurface),
                                                    ),
                                                if (leave['approvedBy'] != null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                        'Approved by: ${leave['approvedBy']}',
                                                        style: TextStyle(color: _leaveColor),
                                                    ),
                                                ],
                                                if (leave['rejectedBy'] != null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                        'Rejected by: ${leave['rejectedBy']}',
                                                        style: TextStyle(color: colorScheme.error),
                                                    ),
                                                ],
                                            ],
                                        ),
                                    ),
                                ))
                                    .toList(),
                            ],
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

    Future<void> _addHoliday(DateTime date) async {
        final TextEditingController nameController = TextEditingController();
        final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: Text('Add Holiday for ${DateFormat('MMMM dd, yyyy').format(date)}'),
                content: TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                        labelText: 'Holiday Name',
                        hintText: 'Enter holiday name',
                    ),
                    autofocus: true,
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                    ),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Add'),
                    ),
                ],
            ),
        );

        if (result == true && nameController.text.isNotEmpty) {
            try {
                // Check if a holiday already exists for this date
                final existingHolidays = await FirebaseFirestore.instance
                    .collection('Leave Calendar')
                    .where('holidayDate', isEqualTo: Timestamp.fromDate(date))
                    .where('Active', isEqualTo: 'Yes')
                    .get();

                if (existingHolidays.docs.isNotEmpty) {
                    if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('A holiday already exists for this date'),
                                backgroundColor: Colors.orange,
                            ),
                        );
                    }
                    return;
                }

                await FirebaseFirestore.instance.collection('Leave Calendar').add({
                    'holidayName': nameController.text,
                    'holidayDate': Timestamp.fromDate(date),
                    'Active': 'Yes',
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdBy': FirebaseAuth.instance.currentUser?.email,
                    'updatedAt': null,
                    'updatedBy': null,
                    'deletedAt': null,
                    'deletedBy': null,
                });
                _loadEvents();
                if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Holiday added successfully'),
                            backgroundColor: Colors.green,
                        ),
                    );
                }
            } catch (e) {
                if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Error adding holiday: $e'),
                            backgroundColor: Colors.red,
                        ),
                    );
                }
            }
        }
    }

    Future<void> _editHoliday(Map<String, dynamic> holiday) async {
        final TextEditingController nameController = TextEditingController(text: holiday['name'] ?? holiday['holidayName']);
        DateTime holidayDate = (holiday['holidayDate'] as Timestamp).toDate();

        final result = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text('Edit Holiday'),
                content: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.9,
                        maxHeight: MediaQuery.of(context).size.height * 0.8,
                    ),
                    child: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                TextField(
                                    controller: nameController,
                                    decoration: const InputDecoration(
                                        labelText: 'Holiday Name',
                                        hintText: 'Enter holiday name',
                                        border: OutlineInputBorder(),
                                    ),
                                    autofocus: true,
                                ),
                                const SizedBox(height: 16),
                                ListTile(
                                    title: const Text('Date'),
                                    subtitle: Text(DateFormat('yyyy-MM-dd').format(holidayDate)),
                                    trailing: const Icon(Icons.calendar_today),
                                    onTap: () async {
                                        final date = await showDatePicker(
                                            context: context,
                                            initialDate: holidayDate,
                                            firstDate: DateTime(2000),
                                            lastDate: DateTime(2100),
                                        );
                                        if (date != null) {
                                            holidayDate = date;
                                        }
                                    },
                                ),
                                const SizedBox(height: 16),
                                if (holiday['createdBy'] != null)
                                    Row(
                                        children: [
                                            const Icon(Icons.person, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                                child: Text(
                                                    'Created by: ${holiday['createdBy']}',
                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                    overflow: TextOverflow.ellipsis,
                                                ),
                                            ),
                                        ],
                                    ),
                                if (holiday['updatedBy'] != null)
                                    Row(
                                        children: [
                                            const Icon(Icons.update, size: 16, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Expanded(
                                                child: Text(
                                                    'Last updated by: ${holiday['updatedBy']}',
                                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                    overflow: TextOverflow.ellipsis,
                                                ),
                                            ),
                                        ],
                                    ),
                            ],
                        ),
                    ),
                ),
                actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                        ),
                        child: const Text('Save Changes'),
                    ),
                ],
            ),
        );

        if (result == true && nameController.text.isNotEmpty) {
            try {
                await FirebaseFirestore.instance
                    .collection('Leave Calendar')
                    .doc(holiday['id'])
                    .update({
                    'holidayName': nameController.text,
                    'holidayDate': Timestamp.fromDate(holidayDate),
                    'updatedAt': FieldValue.serverTimestamp(),
                    'updatedBy': widget.userEmail,
                });
                _loadEvents();
                if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Holiday updated successfully'),
                            backgroundColor: Colors.green,
                        ),
                    );
                }
            } catch (e) {
                if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Error updating holiday: $e'),
                            backgroundColor: Colors.red,
                        ),
                    );
                }
            }
        }
    }
}

class HolidayPrintScreen extends StatelessWidget {
    final Map<DateTime, List<Map<String, dynamic>>> holidays;
    const HolidayPrintScreen({Key? key, required this.holidays}) : super(key: key);

    List<Map<String, dynamic>> get _flatHolidayList {
        return holidays.entries.expand((entry) => entry.value).toList();
    }

    @override
    Widget build(BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        final holidayList = _flatHolidayList;
        return Scaffold(
            appBar: AppBar(
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                ),
                title: const Text('Holiday List'),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
            ),
            body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Text('Holiday List', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        Table(
                            border: TableBorder.all(),
                            columnWidths: const {
                                0: FixedColumnWidth(40),
                                1: FlexColumnWidth(),
                                2: FlexColumnWidth(),
                            },
                            children: [
                                TableRow(
                                    decoration: BoxDecoration(color: Colors.grey[300]),
                                    children: const [
                                        Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Text('S.No', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Text('Holiday Name', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                ),
                                ...List.generate(holidayList.length, (index) {
                                    final holiday = holidayList[index];
                                    final date = holiday['holidayDate'] is DateTime
                                        ? holiday['holidayDate']
                                        : (holiday['holidayDate'] as Timestamp).toDate();
                                    return TableRow(
                                        children: [
                                            Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Text('${index + 1}'),
                                            ),
                                            Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Text(DateFormat('yyyy-MM-dd').format(date)),
                                            ),
                                            Padding(
                                                padding: const EdgeInsets.all(8.0),
                                                child: Text(holiday['name'] ?? holiday['holidayName'] ?? ''),
                                            ),
                                        ],
                                    );
                                }),
                            ],
                        ),
                        const SizedBox(height: 24),
                        Center(
                            child: ElevatedButton.icon(
                                icon: const Icon(Icons.picture_as_pdf),
                                label: const Text('Download as PDF'),
                                onPressed: () => _exportHolidayListAsPdf(context, holidayList),
                            ),
                        ),
                    ],
                ),
            ),
        );
    }

    void _exportHolidayListAsPdf(BuildContext context, List<Map<String, dynamic>> holidays) async {
        final pdf = pw.Document();
        pdf.addPage(
            pw.Page(
                build: (pw.Context context) {
                    return pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                            pw.Text('Holiday List', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
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
                                                child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                                            ),
                                            pw.Padding(
                                                padding: const pw.EdgeInsets.all(8.0),
                                                child: pw.Text('Holiday Name', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                                            ),
                                        ],
                                    ),
                                    ...List.generate(holidays.length, (index) {
                                        final holiday = holidays[index];
                                        final date = holiday['holidayDate'] is DateTime
                                            ? holiday['holidayDate']
                                            : (holiday['holidayDate'] as Timestamp).toDate();
                                        return pw.TableRow(
                                            children: [
                                                pw.Padding(
                                                    padding: const pw.EdgeInsets.all(8.0),
                                                    child: pw.Text('${index + 1}'),
                                                ),
                                                pw.Padding(
                                                    padding: const pw.EdgeInsets.all(8.0),
                                                    child: pw.Text(DateFormat('yyyy-MM-dd').format(date)),
                                                ),
                                                pw.Padding(
                                                    padding: const pw.EdgeInsets.all(8.0),
                                                    child: pw.Text(holiday['name'] ?? holiday['holidayName'] ?? ''),
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
}