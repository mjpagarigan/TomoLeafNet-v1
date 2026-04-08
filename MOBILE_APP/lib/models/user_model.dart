import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? profilePhotoUrl;
  final DateTime registrationDate;
  final String? locationPreference;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.profilePhotoUrl,
    required this.registrationDate,
    this.locationPreference,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      profilePhotoUrl: data['profilePhotoUrl'],
      registrationDate: (data['registrationDate'] as Timestamp).toDate(),
      locationPreference: data['locationPreference'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      'profilePhotoUrl': profilePhotoUrl,
      'registrationDate': Timestamp.fromDate(registrationDate),
      'locationPreference': locationPreference,
    };
  }
}
