import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../widgets/dashboard_drawer.dart';

class EmployeeLeaveCalendarPage extends StatefulWidget {
  final String userEmail;

  const EmployeeLeaveCalendarPage({Key? key, required this.userEmail})
      : super(key: key);

  @override
  State<EmployeeLeaveCalendarPage> createState() =>
      _EmployeeLeaveCalendarPageState();
}

class _EmployeeLeaveCalendarPageState extends State<EmployeeLeaveCalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = true;
  String _filterType = 'all'; // 'all', 'holidays', 'leaves'

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

      // Load only this employee's approved leaves
      final leavesSnapshot = await FirebaseFirestore.instance
          .collection('leaves')
          .where('email', isEqualTo: widget.userEmail)
          .where('status', whereIn: ['approved', 'approve'])
          .get();

      final Map<DateTime, List<Map<String, dynamic>>> events = {};
      final Map<String, Set<DateTime>> employeeLeaveDates = {}; // Track employee leave dates

      // Process company holidays
      for (var doc in holidaysSnapshot.docs) {
        final data = doc.data();
        DateTime holidayDate;
        if (data['holidayDate'] is Timestamp) {
          holidayDate = (data['holidayDate'] as Timestamp).toDate();
        } else if (data['holidayDate'] is String) {
          holidayDate = DateTime.tryParse(data['holidayDate'] as String? ?? '') ?? DateTime.now();
        } else {
          continue;
        }
        final date = DateTime(holidayDate.year, holidayDate.month, holidayDate.day);
        if (!events.containsKey(date)) {
          events[date] = [];
        }
        events[date]!.add({
          'type': 'company_holiday',
          'name': data['holidayName'] as String? ?? 'Holiday',
          'color': Colors.blue,
          'description': 'Company Holiday',
        });
      }

      // Get employee name
      final userSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.userEmail)
          .limit(1)
          .get();

      final employeeName = userSnapshot.docs.isNotEmpty
          ? (userSnapshot.docs.first.data()['name'] as String? ?? widget.userEmail)
          : widget.userEmail;

      // Process employee's own approved leaves
      for (var doc in leavesSnapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String? ?? '').toLowerCase();

        // Only process approved leaves
        if (status != 'approved' && status != 'approve') continue;

        final startDate = (data['startDate'] is Timestamp)
            ? (data['startDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['startDate']?.toString() ?? '') ?? DateTime.now();
        final endDate = (data['endDate'] is Timestamp)
            ? (data['endDate'] as Timestamp).toDate()
            : DateTime.tryParse(data['endDate']?.toString() ?? '') ?? DateTime.now();
        final leaveType = data['leaveType'] as String? ?? 'Leave';
        final reason = data['reason'] as String?;

        // Initialize employee's leave dates set if not exists
        employeeLeaveDates[widget.userEmail] = employeeLeaveDates[widget.userEmail] ?? {};

        // Add leave for each day in the range
        for (var date = startDate;
        date.isBefore(endDate.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
          final normalizedDate = DateTime(date.year, date.month, date.day);

          // Skip if employee already has a leave on this date
          if (employeeLeaveDates[widget.userEmail]!.contains(normalizedDate)) {
            continue;
          }

          employeeLeaveDates[widget.userEmail]!.add(normalizedDate);

          if (!events.containsKey(normalizedDate)) {
            events[normalizedDate] = [];
          }
          events[normalizedDate]!.add({
            'type': 'leave',
            'name': leaveType,
            'employeeName': employeeName,
            'reason': reason,
            'startDate': startDate,
            'endDate': endDate,
            'color': Colors.green,
            'description': 'Personal Leave',
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
        tooltipLines.add('• ${leave['name']} ($duration days)');
      }
    }

    return tooltipLines.join('\n');
  }

  void _showDayEvents(DateTime day) {
    final events = _getFilteredEvents(day);
    if (events.isEmpty) return;

    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colorScheme.surface,
        title: Text(
          DateFormat('MMMM dd, yyyy').format(day),
          style: TextStyle(color: colorScheme.onSurface),
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    'Company Holiday',
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
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
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                ...events
                    .where((e) => e['type'] == 'leave')
                    .map((leave) => ListTile(
                  leading: const Icon(Icons.person, color: Colors.green),
                  title: Text(
                    leave['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Duration: ${DateFormat('MMM dd').format(leave['startDate'])} - ${DateFormat('MMM dd, yyyy').format(leave['endDate'])}',
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                      ),
                      if (leave['reason'] != null && leave['reason'].toString().isNotEmpty)
                        Text(
                          'Reason: ${leave['reason']}',
                          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                        ),
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
            child: Text(
              'Close',
              style: TextStyle(color: colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Leave Calendar'),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      drawer: DashboardDrawer(
        onThemeChanged: () {
          setState(() {});
        },
        userEmail: widget.userEmail,
      ),
      backgroundColor: colorScheme.surface,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Column(
        children: [
          // Filter chips
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    label: Text(
                      'All',
                      style: TextStyle(
                        color: _filterType == 'all'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _filterType == 'all',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'all';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'Holidays',
                      style: TextStyle(
                        color: _filterType == 'holidays'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _filterType == 'holidays',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'holidays';
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'Leaves',
                      style: TextStyle(
                        color: _filterType == 'leaves'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _filterType == 'leaves',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (selected) {
                      setState(() {
                        _filterType = 'leaves';
                      });
                    },
                  ),
                ],
              ),
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
              weekendTextStyle: TextStyle(color: colorScheme.error),
              defaultTextStyle: TextStyle(color: colorScheme.onSurface),
              selectedTextStyle: TextStyle(color: colorScheme.onPrimary),
              todayTextStyle: TextStyle(color: colorScheme.onPrimary),
              outsideTextStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
            ),
            headerStyle: HeaderStyle(
              titleTextStyle: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              formatButtonTextStyle: TextStyle(color: colorScheme.primary),
              formatButtonDecoration: BoxDecoration(
                border: Border.all(color: colorScheme.primary),
                borderRadius: BorderRadius.circular(12),
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
                        Icon(Icons.event, size: 16, color: colorScheme.primary),
                      if (hasLeave)
                        Icon(Icons.person, size: 16, color: colorScheme.secondary),
                    ],
                  ),
                );
              },
            ),
            eventLoader: _getFilteredEvents,
          ),
          const SizedBox(height: 16),
          // Legend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Holiday', Colors.blue, colorScheme),
                const SizedBox(width: 16),
                _buildLegendItem('Leave', Colors.green, colorScheme),
              ],
            ),
          ),
          // Upcoming Holidays List
          Expanded(
            child: _buildUpcomingHolidaysList(colorScheme),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingHolidaysList(ColorScheme colorScheme) {
    // Get upcoming holidays (next 30 days)
    final now = DateTime.now();
    final upcomingHolidays = <Map<String, dynamic>>[];

    for (var entry in _events.entries) {
      final date = entry.key;
      final events = entry.value;

      if (date.isAfter(now) && date.isBefore(now.add(const Duration(days: 30)))) {
        for (var event in events) {
          if (event['type'] == 'company_holiday') {
            upcomingHolidays.add({
              'date': date,
              'name': event['name'],
              ...event,
            });
          }
        }
      }
    }

    // Sort by date
    upcomingHolidays.sort((a, b) => a['date'].compareTo(b['date']));

    if (upcomingHolidays.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_busy,
                size: 48,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Text(
                'No upcoming holidays',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event,
                  color: colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Upcoming Holidays',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: upcomingHolidays.length,
              itemBuilder: (context, index) {
                final holiday = upcomingHolidays[index];
                final date = holiday['date'] as DateTime;
                final daysUntil = date.difference(now).inDays;

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  color: colorScheme.surfaceVariant,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: colorScheme.outline.withOpacity(0.2),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          date.day.toString(),
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      holiday['name'] ?? 'Holiday',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      DateFormat('EEEE, MMMM dd, yyyy').format(date),
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        daysUntil == 0
                            ? 'Today'
                            : daysUntil == 1
                            ? 'Tomorrow'
                            : '$daysUntil days',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
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
}