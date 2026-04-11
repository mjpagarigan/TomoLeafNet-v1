import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/reminder_model.dart';

/// Firestore CRUD for reminders stored under
/// `users/{uid}/reminders/{reminderId}`.
class ReminderService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('reminders');

  /// Create a new reminder. Generates the document ID.
  Future<ReminderModel> createReminder({
    required String uid,
    required ReminderCategory category,
    required String plantName,
    String? plantImageUrl,
    String? waterAmount,
    required ReminderRepeat repeat,
    required DateTime startDate,
    required TimeOfDay notifyTime,
    String? fcmToken,
  }) async {
    final docRef = _col(uid).doc();
    final reminder = ReminderModel(
      reminderId: docRef.id,
      category: category,
      plantName: plantName,
      plantImageUrl: plantImageUrl,
      waterAmount: waterAmount,
      repeat: repeat,
      startDate: startDate,
      notifyTime: notifyTime,
      isCompleted: false,
      isExpired: false,
      fcmToken: fcmToken,
      createdAt: DateTime.now(),
    );
    await docRef.set(reminder.toFirestore());
    return reminder;
  }

  /// Update an existing reminder by writing the full model back.
  Future<void> updateReminder(String uid, ReminderModel reminder) async {
    await _col(uid).doc(reminder.reminderId).set(reminder.toFirestore());
  }

  /// Patch a single field on an existing reminder.
  Future<void> patchReminder(
    String uid,
    String reminderId,
    Map<String, dynamic> data,
  ) async {
    await _col(uid).doc(reminderId).update(data);
  }

  /// Mark a reminder as completed.
  Future<void> markCompleted(String uid, String reminderId, bool completed) async {
    await patchReminder(uid, reminderId, {'isCompleted': completed});
  }

  /// Mark a reminder as expired.
  Future<void> markExpired(String uid, String reminderId, bool expired) async {
    await patchReminder(uid, reminderId, {'isExpired': expired});
  }

  /// Delete a reminder document.
  Future<void> deleteReminder(String uid, String reminderId) async {
    await _col(uid).doc(reminderId).delete();
  }

  /// Real-time stream of all reminders for the user, ordered by createdAt asc.
  Stream<List<ReminderModel>> streamReminders(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(ReminderModel.fromFirestore).toList());
  }
}
