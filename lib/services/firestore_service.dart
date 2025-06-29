import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final CollectionReference employees =
  FirebaseFirestore.instance.collection('employees');

  Future<void> addEmployee(String name, String email, String role) {
    return employees.add({
      'name': name,
      'email': email,
      'role': role,
      'attendance': [],
    });
  }

  Stream<QuerySnapshot> getEmployees() {
    return employees.snapshots();
  }

  Future<void> updateEmployee(String id, Map<String, dynamic> data) {
    return employees.doc(id).update(data);
  }

  Future<void> deleteEmployee(String id) {
    return employees.doc(id).delete();
  }
}
