import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EmployeeLeaveRequestsPage extends StatefulWidget {
  final String email;
  const EmployeeLeaveRequestsPage({Key? key, required this.email}) : super(key: key);

  @override
  State<EmployeeLeaveRequestsPage> createState() => _EmployeeLeaveRequestsPageState();
}

class _EmployeeLeaveRequestsPageState extends State<EmployeeLeaveRequestsPage> {
  String _statusFilter = 'all';

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'approve':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'My Leave Requests',
          style: TextStyle(color: colorScheme.onPrimary),
        ),
        backgroundColor: colorScheme.primary,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilterChip(
                    label: Text(
                      'All',
                      style: TextStyle(
                        color: _statusFilter == 'all'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _statusFilter == 'all',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (_) => setState(() => _statusFilter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'Approved',
                      style: TextStyle(
                        color: _statusFilter == 'approved'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _statusFilter == 'approved',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (_) => setState(() => _statusFilter = 'approved'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'Rejected',
                      style: TextStyle(
                        color: _statusFilter == 'rejected'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _statusFilter == 'rejected',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (_) => setState(() => _statusFilter = 'rejected'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      'Pending',
                      style: TextStyle(
                        color: _statusFilter == 'pending'
                            ? colorScheme.onPrimary
                            : colorScheme.onSurface,
                      ),
                    ),
                    selected: _statusFilter == 'pending',
                    selectedColor: colorScheme.primary,
                    backgroundColor: colorScheme.surfaceVariant,
                    onSelected: (_) => setState(() => _statusFilter = 'pending'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('leaves')
                  .where('email', isEqualTo: widget.email)
                  .orderBy('appliedOn', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: colorScheme.error),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: colorScheme.primary),
                  );
                }
                final leaves = snapshot.data?.docs ?? [];
                final filteredLeaves = _statusFilter == 'all'
                    ? leaves
                    : leaves.where((doc) => _statusFilter == 'approved' ? ((doc['status'] ?? '').toString().toLowerCase() == 'approved' || (doc['status'] ?? '').toString().toLowerCase() == 'approve') : (doc['status'] ?? '').toString().toLowerCase() == _statusFilter).toList();
                if (filteredLeaves.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 64,
                          color: colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No leave requests found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusFilter == 'all'
                              ? 'Apply for leave to get started'
                              : 'No ${_statusFilter} leave requests',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredLeaves.length,
                  itemBuilder: (context, index) {
                    final data = filteredLeaves[index].data() as Map<String, dynamic>;
                    final leaveType = data['leaveType'] ?? 'Leave';
                    final status = (data['status'] ?? 'pending').toString().toLowerCase();
                    final reason = data['reason'] as String? ?? '';
                    final approvalReason = data['approvalReason'] as String? ?? '';
                    final rejectionReason = data['rejectionReason'] as String? ?? '';
                    final actionedBy = data['actionedBy'] as String? ?? '';
                    final actionedOn = data['actionedOn'] != null
                        ? (data['actionedOn'] is Timestamp
                        ? (data['actionedOn'] as Timestamp).toDate()
                        : DateTime.tryParse(data['actionedOn'].toString()))
                        : null;
                    final startDate = data['startDate'] is Timestamp
                        ? (data['startDate'] as Timestamp).toDate()
                        : DateTime.tryParse(data['startDate'].toString()) ?? DateTime.now();
                    final endDate = data['endDate'] is Timestamp
                        ? (data['endDate'] as Timestamp).toDate()
                        : DateTime.tryParse(data['endDate'].toString()) ?? DateTime.now();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      color: colorScheme.surface,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  leaveType,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status.toUpperCase(),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildInfoRow(
                              Icons.date_range,
                              'From',
                              DateFormat('MMM dd, yyyy').format(startDate),
                              colorScheme,
                            ),
                            const SizedBox(height: 8),
                            _buildInfoRow(
                              Icons.date_range,
                              'To',
                              DateFormat('MMM dd, yyyy').format(endDate),
                              colorScheme,
                            ),
                            if (reason.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                Icons.notes,
                                'Reason',
                                reason,
                                colorScheme,
                              ),
                            ],
                            if (status == 'approved' || status == 'approve') ...[
                              if (approvalReason.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.check_circle,
                                  'Approval Note',
                                  approvalReason,
                                  colorScheme,
                                  textColor: Colors.green,
                                ),
                              ],
                              if (actionedBy.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.person,
                                  'Approved by',
                                  actionedBy,
                                  colorScheme,
                                  textColor: Colors.green,
                                ),
                                if (actionedOn != null) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    Icons.update,
                                    'Approved on',
                                    DateFormat('MMM dd, yyyy').format(actionedOn),
                                    colorScheme,
                                    textColor: Colors.green,
                                  ),
                                ],
                              ],
                            ],
                            if (status == 'rejected') ...[
                              if (rejectionReason.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.cancel,
                                  'Rejection Note',
                                  rejectionReason,
                                  colorScheme,
                                  textColor: Colors.red,
                                ),
                              ],
                              if (actionedBy.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildInfoRow(
                                  Icons.person,
                                  'Rejected by',
                                  actionedBy,
                                  colorScheme,
                                  textColor: Colors.red,
                                ),
                                if (actionedOn != null) ...[
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    Icons.update,
                                    'Rejected on',
                                    DateFormat('MMM dd, yyyy').format(actionedOn),
                                    colorScheme,
                                    textColor: Colors.red,
                                  ),
                                ],
                              ],
                            ],
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
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, ColorScheme colorScheme, {Color? textColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 20,
          color: textColor ?? colorScheme.onSurface.withOpacity(0.7),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor ?? colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}