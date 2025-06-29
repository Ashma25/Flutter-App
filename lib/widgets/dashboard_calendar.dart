import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class DashboardCalendar extends StatefulWidget {
  final String userEmail;
  final String? userRole;

  const DashboardCalendar({
    Key? key,
    required this.userEmail,
    this.userRole,
  }) : super(key: key);

  @override
  State<DashboardCalendar> createState() => _DashboardCalendarState();
}

class _DashboardCalendarState extends State<DashboardCalendar> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = true;
  String _filterType = 'all'; // 'all', 'holidays', 'leaves'
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
      _events.clear();

      // Load company holidays
      final holidaysSnapshot = await FirebaseFirestore.instance
          .collection('Leave Calendar')
          .where('Active', isEqualTo: 'Yes')
          .get();

      // Load leaves based on user role
      QuerySnapshot leavesSnapshot;
      if (widget.userRole?.toLowerCase() == 'admin') {
        // Admin sees all approved leaves
        leavesSnapshot = await FirebaseFirestore.instance
            .collection('leaves')
            .where('status', whereIn: ['approved', 'approve'])
            .get();
      } else {
        // Regular users see only their approved leaves
        leavesSnapshot = await FirebaseFirestore.instance
            .collection('leaves')
            .where('email', isEqualTo: widget.userEmail)
            .where('status', whereIn: ['approved', 'approve'])
            .get();
      }

      final Map<DateTime, List<Map<String, dynamic>>> events = {};
      final Map<String, Set<DateTime>> employeeLeaveDates = {}; // Track employee leave dates

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
        events[date]!.add({
          'type': 'company_holiday',
          'name': data['holidayName'],
          'color': Colors.blue,
          'description': 'Company Holiday',
        });
      }

      // Get all employee names in one query
      final employeeEmails = leavesSnapshot.docs
          .map((doc) => (doc.data() as Map<String, dynamic>)['email'] as String? ?? '')
          .where((email) => email.isNotEmpty)
          .toSet();
      Map<String, String> employeeNames = {};
      if (employeeEmails.isNotEmpty) {
        final usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('email', whereIn: employeeEmails.toList())
            .get();

        employeeNames = {
          for (var doc in usersSnapshot.docs)
            doc.data()['email'] as String: doc.data()['name'] as String
        };
      }

      // Process employee leaves
      for (var doc in leavesSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final status = (data['status'] as String? ?? '').toLowerCase();

        // Only process approved leaves
        if (status != 'approved' && status != 'approve') continue;

        final startDate = (data['startDate'] is Timestamp)
            ? (data['startDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['startDate']?.toString() ?? '') ?? DateTime.now();
        final endDate = (data['endDate'] is Timestamp)
            ? (data['endDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['endDate']?.toString() ?? '') ?? DateTime.now();
        final email = data['email'] as String? ?? '';
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
            'color': Colors.green,
            'description': 'Employee Leave',
            'status': status,
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

  void _showDayEvents(DateTime day) {
    final events = _getFilteredEvents(day);
    if (events.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(DateFormat('MMMM dd, yyyy').format(day)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Holidays section
              if (events.any((e) => e['type'] == 'company_holiday')) ...[
                const Text(
                  'Holidays',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                ...events
                    .where((e) => e['type'] == 'company_holiday')
                    .map((holiday) => ListTile(
                  leading: const Icon(Icons.event, color: Colors.blue),
                  title: Text(
                    holiday['name'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Company Holiday'),
                ))
                    .toList(),
                const Divider(),
              ],
              // Leaves section
              if (events.any((e) => e['type'] == 'leave')) ...[
                const Text(
                  'Leaves',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                ...events
                    .where((e) => e['type'] == 'leave')
                    .map((leave) => ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(
                    leave['employeeName'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type: ${leave['name']}'),
                      Text(
                        'Duration: ${DateFormat('MMM dd').format(leave['startDate'])} - ${DateFormat('MMM dd, yyyy').format(leave['endDate'])}',
                      ),
                      if (leave['reason'] != null && leave['reason'].toString().isNotEmpty)
                        Text('Reason: ${leave['reason']}'),
                    ],
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

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Filter chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filterType == 'all',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'all';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Holidays'),
                    selected: _filterType == 'holidays',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'holidays';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Leaves'),
                    selected: _filterType == 'leaves',
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'leaves';
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Calendar
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
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary,
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
                          const Icon(
                            Icons.event,
                            size: 12,
                            color: Colors.blue,
                          ),
                        if (hasLeave)
                          const Icon(
                            Icons.person,
                            size: 12,
                            color: Colors.green,
                          ),
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
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              holiday['name'],
                              style: const TextStyle(
                                fontSize: 8,
                                color: Colors.blue,
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
                              color: Colors.green.withOpacity(0.1),
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
                                  style: const TextStyle(
                                    fontSize: 7,
                                    color: Colors.green,
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
              eventLoader: _getFilteredEvents,
            ),
            const SizedBox(height: 16),
            // Legend
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Holiday', Colors.blue, Icons.event),
                const SizedBox(width: 16),
                _buildLegendItem('Leave', Colors.green, Icons.person),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}