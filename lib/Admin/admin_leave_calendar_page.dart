import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../widgets/dashboard_drawer.dart';

class AdminLeaveCalendarPage extends StatefulWidget {
  final String userEmail;
  const AdminLeaveCalendarPage({Key? key, required this.userEmail}) : super(key: key);

  @override
  State<AdminLeaveCalendarPage> createState() => _AdminLeaveCalendarPageState();
}

class _AdminLeaveCalendarPageState extends State<AdminLeaveCalendarPage> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<Map<String, dynamic>>> _events = {};
  bool _isLoading = true;
  List<Map<String, dynamic>> _monthlyLeaves = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      // Fetch holidays
      final holidaysSnapshot = await FirebaseFirestore.instance
          .collection('Leave Calendar')
          .where('Active', isEqualTo: 'Yes')
          .get();
      // Fetch all approved leaves
      final leavesSnapshot = await FirebaseFirestore.instance
          .collection('leaves')
          .where('status', isEqualTo: 'approved')
          .get();
      final Map<DateTime, List<Map<String, dynamic>>> events = {};
      List<Map<String, dynamic>> monthlyLeaves = [];
      // Process holidays
      for (var doc in holidaysSnapshot.docs) {
        final data = doc.data();
        DateTime holidayDate = (data['holidayDate'] as Timestamp).toDate();
        final date = DateTime(holidayDate.year, holidayDate.month, holidayDate.day);
        if (!events.containsKey(date)) events[date] = [];
        events[date]!.add({
          'type': 'holiday',
          'id': doc.id,
          'name': data['holidayName'],
          'color': Colors.blue,
          ...data,
        });
      }
      // Process leaves
      for (var doc in leavesSnapshot.docs) {
        final data = doc.data();
        final startDate = (data['startDate'] as Timestamp).toDate();
        final endDate = (data['endDate'] as Timestamp).toDate();
        for (var date = startDate;
        date.isBefore(endDate.add(const Duration(days: 1)));
        date = date.add(const Duration(days: 1))) {
          final normalizedDate = DateTime(date.year, date.month, date.day);
          if (!events.containsKey(normalizedDate)) events[normalizedDate] = [];
          events[normalizedDate]!.add({
            'type': 'leave',
            'id': doc.id,
            'name': data['leaveType'] ?? 'Leave',
            'employee': data['email'] ?? '',
            'color': Colors.green,
            ...data,
          });
        }
        // For monthly list
        if (startDate.year == _focusedDay.year && startDate.month == _focusedDay.month) {
          monthlyLeaves.add({
            'id': doc.id,
            'employee': data['email'] ?? '',
            'leaveType': data['leaveType'] ?? 'Leave',
            'startDate': startDate,
            'endDate': endDate,
            'reason': data['reason'] ?? '',
            'status': data['status'] ?? '',
          });
        }
      }
      setState(() {
        _events = events;
        _monthlyLeaves = monthlyLeaves;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading events: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  bool _isWeekend(DateTime day) {
    return day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
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
                      const SnackBar(content: Text('Holiday added successfully'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error adding holiday: $e'), backgroundColor: Colors.red),
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

  Future<void> _showEditHolidayDialog(Map<String, dynamic> holiday) async {
    final TextEditingController nameController = TextEditingController(text: holiday['name']);
    DateTime selectedDate = (holiday['holidayDate'] is Timestamp)
        ? (holiday['holidayDate'] as Timestamp).toDate()
        : DateTime.parse(holiday['holidayDate'].toString());
    await showDialog(
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
                      .doc(holiday['id'])
                      .update({
                    'holidayName': nameController.text,
                    'holidayDate': Timestamp.fromDate(selectedDate),
                    'updatedBy': widget.userEmail,
                    'updatedOn': FieldValue.serverTimestamp(),
                  });
                  if (mounted) {
                    Navigator.pop(context);
                    _loadEvents();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Holiday updated successfully'), backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating holiday: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHoliday(String holidayId) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Holiday'),
        content: const Text('Are you sure you want to delete this holiday?'),
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
            const SnackBar(content: Text('Holiday deleted successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting holiday: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  void _showDayEvents(DateTime day) {
    final events = _getEventsForDay(day);
    if (events.isEmpty) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(DateFormat('MMMM d, yyyy').format(day)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: events.map((event) {
            if (event['type'] == 'holiday') {
              return ListTile(
                title: Text(event['name']),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blue),
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditHolidayDialog(event);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteHoliday(event['id']);
                      },
                    ),
                  ],
                ),
              );
            } else {
              return ListTile(
                title: Text(event['name']),
                subtitle: Text('Employee: ${event['employee'] ?? ''}'),
              );
            }
          }).toList(),
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
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Leave Calendar'),
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
        userEmail: widget.userEmail,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : Column(
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
              setState(() => _calendarFormat = format);
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
              _loadEvents();
            },
            calendarStyle: CalendarStyle(
              markersMaxCount: 3,
              weekendTextStyle: TextStyle(color: colorScheme.error),
              todayDecoration: BoxDecoration(
                color: colorScheme.secondary.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (context, day, focusedDay) {
                if (_isWeekend(day)) {
                  return Container(
                    decoration: BoxDecoration(
                      color: colorScheme.error.withOpacity(0.2),
                      shape: BoxShape.rectangle,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${day.day}',
                        style: TextStyle(color: colorScheme.error),
                      ),
                    ),
                  );
                }
                return null;
              },
              markerBuilder: (context, date, events) {
                if (events.isNotEmpty) {
                  final hasHoliday = events.any((e) => e is Map<String, dynamic> && e['type'] == 'holiday');
                  if (hasHoliday) {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: events.take(3).map((event) {
                        if (event is Map<String, dynamic> && event['type'] == 'holiday') {
                          final color = event['color'] as Color;
                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          );
                        }
                        return null;
                      }).whereType<Widget>().toList(),
                    );
                  }
                }
                return null;
              },
            ),
            eventLoader: _getEventsForDay,
          ),
          // Upcoming Holidays List (scrollable, all holidays for the month)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Upcoming Holidays',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    shrinkWrap: true,
                    children: _events.entries
                        .where((entry) => entry.value.any((e) => e['type'] == 'holiday') && entry.key.month == _focusedDay.month && entry.key.year == _focusedDay.year)
                        .expand((entry) => entry.value.where((e) => e['type'] == 'holiday').map((holiday) => ListTile(
                      leading: const Icon(Icons.event, color: Colors.blue),
                      title: Text(holiday['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Company Holiday'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: () {
                              _showEditHolidayDialog(holiday);
                            },
                            tooltip: 'Edit Holiday',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final bool? confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Delete Holiday'),
                                  content: const Text('Are you sure you want to delete this holiday?'),
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
                              if (confirm == true) {
                                _deleteHoliday(holiday['id']);
                              }
                            },
                            tooltip: 'Delete Holiday',
                          ),
                        ],
                      ),
                    )))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Leaves for ${DateFormat('MMMM yyyy').format(_focusedDay)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _monthlyLeaves.length,
                    itemBuilder: (context, index) {
                      final leave = _monthlyLeaves[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: ListTile(
                          title: Text(leave['leaveType'] ?? ''),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${DateFormat('MMM d').format(leave['startDate'] ?? DateTime.now())} - ${DateFormat('MMM d, yyyy').format(leave['endDate'] ?? DateTime.now())}'),
                              Text('Reason: ${leave['reason'] ?? ''}'),
                              Text('Status: ${(leave['status'] ?? '').toUpperCase()}'),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddHolidayDialog,
        backgroundColor: colorScheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}