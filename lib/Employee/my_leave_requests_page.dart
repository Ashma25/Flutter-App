import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MyLeaveRequestsPage extends StatelessWidget {
  final String userEmail;
  const MyLeaveRequestsPage({Key? key, required this.userEmail}) : super(key: key);

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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('leaves')
            .where('email', isEqualTo: userEmail)
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
          if (leaves.isEmpty) {
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
                    'Apply for leave to get started',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            itemCount: leaves.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final data = leaves[index].data() as Map<String, dynamic>;
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
              final status = (data['status'] as String? ?? '').toLowerCase();
              final leaveType = data['leaveType'] ?? 'Unknown';
              final reason = data['reason'] as String? ?? '';
              final approvalReason = data['approvalReason'] as String? ?? '';
              final rejectionReason = data['rejectionReason'] as String? ?? '';
              final actionedBy = data['actionedBy'] as String? ?? '';
              final actionedOn = data['actionedOn'] != null ? parseDate(data['actionedOn']) : null;

              Color getStatusColor(String status) {
                switch (status) {
                  case 'approved':
                  case 'approve':
                    return Colors.green;
                  case 'rejected':
                    return Colors.red;
                  default:
                    return Colors.orange;
                }
              }

              final statusColor = getStatusColor(status);

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
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        Icons.access_time,
                        'Applied on',
                        DateFormat('MMM dd, yyyy').format(appliedOn),
                        colorScheme,
                      ),
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