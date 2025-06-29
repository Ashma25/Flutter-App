import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/dashboard_calendar.dart';
import '../widgets/dashboard_drawer.dart';
import 'leave_page.dart';
import 'admin_employee_masters.dart';
import 'view_profile_page.dart';
import 'animated_login_screen.dart';
import 'attendance_page.dart';
import 'employee_leave_calendar_page.dart';
import 'leave_calendar_page.dart';
import 'employee_leave_requests_page.dart' as emp_leave_req;
import 'policy_page.dart';

class DashboardPage extends StatefulWidget {
  final String email;
  final String? role;

  const DashboardPage({Key? key, required this.email, this.role})
      : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  String? userName;
  String? userRole;
  bool isLoading = true;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late AnimationController _animationController;

  final List<_DashboardCardData> cards = [
    const _DashboardCardData(
      title: 'Attendance',
      color: Colors.indigo,
      icon: Icons.access_time_filled,
      onTapRoute: '/attendance',
      description: 'View attendance and QR code check-in/out.',
    ),
    const _DashboardCardData(
      title: 'Leave',
      color: Colors.teal,
      icon: Icons.beach_access,
      onTapRoute: '/leave',
      description: 'Apply or view your leaves.',
    ),
    const _DashboardCardData(
      title: 'Leave Calendar',
      color: Colors.deepOrange,
      icon: Icons.calendar_month,
      onTapRoute: '/leaveTable',
      description: 'See leave records.',
    ),
  ];

  List<_DashboardCardData> get _filteredCards {
    final List<_DashboardCardData> filteredCards = List.from(cards);

    if (userRole?.toLowerCase() == 'admin') {
      filteredCards.addAll([
        const _DashboardCardData(
          title: 'Employee Master',
          color: Colors.deepPurple,
          icon: Icons.people,
          onTapRoute: '/employee-master',
          description: 'Manage employee.',
        ),
        const _DashboardCardData(
          title: 'Code Master',
          color: Colors.blueGrey,
          icon: Icons.code,
          onTapRoute: '/codeMaster',
          description: 'Manage codes and types.',
        ),
        const _DashboardCardData(
          title: 'Policies',
          color: Colors.orange,
          icon: Icons.policy,
          onTapRoute: '/policies',
          description: 'Manage company policies.',
        ),
      ]);
    } else {
      // Add My Profile and Policies for employees
      filteredCards.addAll([
        const _DashboardCardData(
          title: 'My Profile',
          color: Colors.deepPurple,
          icon: Icons.supervisor_account,
          onTapRoute: '/employeeProfile',
          description: 'View  profile',
        ),
        const _DashboardCardData(
          title: 'Policies',
          color: Colors.orange,
          icon: Icons.policy,
          onTapRoute: '/policies',
          description: 'View company policies.',
        ),
      ]);
    }

    return filteredCards;
  }

  @override
  void initState() {
    super.initState();
    fetchUserName();
    _loadUserRole();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _animationController.forward(from: 0);
    });
  }

  Future<void> fetchUserName() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final userData = snapshot.docs.first.data();
        setState(() {
          userName = userData['name']?.toString();
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  Future<void> _loadUserRole() async {
    try {
      final QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final userData = querySnapshot.docs.first.data() as Map<String, dynamic>?;
        if (userData != null) {
          final role = userData['role']?.toString();
          setState(() {
            userRole = role;
            isLoading = false;
          });
        } else {
          setState(() {
            userRole = null;
            isLoading = false;
          });
        }
      } else {
        setState(() {
          userRole = null;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  void _handleCardTap(String title) {
    switch (title) {
      case 'Employee Master':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                AdminEmployeeMasterPage(userEmail: widget.email),
          ),
        );
        break;
      case 'My Profile':
        Navigator.pushNamed(context, '/employeeProfile',
            arguments: widget.email);
        break;
      case 'Code Master':
        Navigator.pushNamed(
          context,
          '/codeMaster',
          arguments: {'email': widget.email, 'role': userRole},
        );
        break;
      case 'Leave Calendar':
        if (userRole?.toLowerCase() == 'admin') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => LeaveCalendarPage(userEmail: widget.email),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EmployeeLeaveCalendarPage(userEmail: widget.email),
            ),
          );
        }
        break;
      case 'Attendance':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AttendancePage(
              email: widget.email,
              isAdmin: userRole?.toLowerCase() == 'admin',
            ),
          ),
        );
        break;
      case 'Leave':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LeavePage(email: widget.email),
          ),
        );
        break;
      case 'Leave Table':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leave Table feature coming soon!'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case 'View Profile':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ViewProfilePage(email: widget.email),
          ),
        );
        break;
      case 'Apply Leave':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => LeavePage(email: widget.email),
          ),
        );
        break;
      case 'Leave Request':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => emp_leave_req.EmployeeLeaveRequestsPage(email: widget.email),
          ),
        );
        break;
      case 'Policies':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PolicyPage(
              email: widget.email,
              role: userRole,
            ),
          ),
        );
        break;
    }
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(
            color: Color(0xFF2C3E50),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2C3E50),
            ),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C3E50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (shouldLogout == true && mounted) {
      // Set isLoggedIn to false in Firestore for this user
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: widget.email)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(query.docs.first.id)
            .update({'isLoggedIn': false});
      }
      await _signOut();
    }
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AnimatedLoginScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      // Handle error silently
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (isLoading) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Dashboard',
          style: TextStyle(
            color: colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: colorScheme.primary,
        leading: IconButton(
          icon: Icon(Icons.menu, color: colorScheme.onPrimary),
          onPressed: _openDrawer,
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: colorScheme.onPrimary),
            onPressed: _loadUserRole,
          ),
        ],
      ),
      drawer: DashboardDrawer(
        onThemeChanged: () {
          setState(() {}); // Rebuild to reflect theme change
        },
        userEmail: widget.email,
        userName: userName,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add the calendar at the top
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DashboardCalendar(
                userEmail: widget.email,
                userRole: userRole,
              ),
            ),
            const SizedBox(height: 16),
            // Dynamic cards based on user role
            Column(
              children: [
                if (userRole?.toLowerCase() == 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Employee Master',
                        color: Colors.deepPurple,
                        icon: Icons.people,
                        onTapRoute: '/employee-master',
                        description: 'Manage employee.',
                      ),
                    ),
                  ),
                if (userRole?.toLowerCase() != 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'My Profile',
                        color: Colors.deepPurple,
                        icon: Icons.person,
                        onTapRoute: '/employeeProfile',
                        description: 'View and edit your profile.',
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _buildDashboardCard(
                    const _DashboardCardData(
                      title: 'Attendance',
                      color: Colors.indigo,
                      icon: Icons.access_time,
                      onTapRoute: '/attendance',
                      description: 'View attendance.',
                    ),
                  ),
                ),
                if (userRole?.toLowerCase() != 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Apply Leave',
                        color: Colors.teal,
                        icon: Icons.add_circle,
                        onTapRoute: '/leave',
                        description: 'Apply for a new leave.',
                      ),
                    ),
                  ),
                if (userRole?.toLowerCase() != 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Leave Request',
                        color: Colors.orange,
                        icon: Icons.list_alt,
                        onTapRoute: '/leave-requests',
                        description: 'View your leave requests.',
                      ),
                    ),
                  ),
                if (userRole?.toLowerCase() == 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Leave',
                        color: Colors.teal,
                        icon: Icons.beach_access,
                        onTapRoute: '/leave',
                        description: 'Apply or view your leaves.',
                      ),
                    ),
                  ),
                if (userRole?.toLowerCase() == 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Leave Calendar',
                        color: Colors.deepOrange,
                        icon: Icons.calendar_today,
                        onTapRoute: '/leave-calendar',
                        description: 'View company holidays.',
                      ),
                    ),
                  ),
                if (userRole?.toLowerCase() == 'admin')
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: _buildDashboardCard(
                      const _DashboardCardData(
                        title: 'Code Master',
                        color: Colors.blueGrey,
                        icon: Icons.code,
                        onTapRoute: '/codeMaster',
                        description: 'Manage codes and types.',
                      ),
                    ),
                  ),
                // Add Policy card for both admin and employees
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: _buildDashboardCard(
                    _DashboardCardData(
                      title: 'Policies',
                      color: Colors.orange,
                      icon: Icons.policy,
                      onTapRoute: '/policies',
                      description: userRole?.toLowerCase() == 'admin'
                          ? 'Manage company policies.'
                          : 'View company policies.',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(_DashboardCardData card) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
      child: GestureDetector(
        onTap: () => _handleCardTap(card.title),
        child: Container(
          width: double.infinity,
          height: 110,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                card.color.withValues(alpha: 0.95),
                card.color.withValues(alpha: 0.75),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: card.color.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(card.icon, size: 48, color: Colors.white),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      card.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.description,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios,
                  color: Colors.white, size: 26),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardCardData {
  final String title;
  final Color color;
  final IconData icon;
  final String onTapRoute;
  final String description;
  const _DashboardCardData({
    required this.title,
    required this.color,
    required this.icon,
    required this.onTapRoute,
    required this.description,
  });
}