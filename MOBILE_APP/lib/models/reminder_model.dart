import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Supported reminder categories. The string value is what is persisted in
/// Firestore and sent to the backend scheduler.
enum ReminderCategory {
  watering,
  repotting,
  cutting,
  fertilize,
  supportStems,
  checkSoil,
  other,
}

extension ReminderCategoryX on ReminderCategory {
  String get value {
    switch (this) {
      case ReminderCategory.watering:
        return 'watering';
      case ReminderCategory.repotting:
        return 'repotting';
      case ReminderCategory.cutting:
        return 'cutting';
      case ReminderCategory.fertilize:
        return 'fertilize';
      case ReminderCategory.supportStems:
        return 'support_stems';
      case ReminderCategory.checkSoil:
        return 'check_soil';
      case ReminderCategory.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case ReminderCategory.watering:
        return 'Watering';
      case ReminderCategory.repotting:
        return 'Repotting';
      case ReminderCategory.cutting:
        return 'Cutting';
      case ReminderCategory.fertilize:
        return 'Fertilize';
      case ReminderCategory.supportStems:
        return 'Support Stems';
      case ReminderCategory.checkSoil:
        return 'Check Soil Moisture';
      case ReminderCategory.other:
        return 'Other';
    }
  }

  /// Verb form used in notification body text — "Time to water your X".
  String get verb {
    switch (this) {
      case ReminderCategory.watering:
        return 'water';
      case ReminderCategory.repotting:
        return 'repot';
      case ReminderCategory.cutting:
        return 'prune';
      case ReminderCategory.fertilize:
        return 'fertilize';
      case ReminderCategory.supportStems:
        return 'check the support stems on';
      case ReminderCategory.checkSoil:
        return 'check the soil moisture on';
      case ReminderCategory.other:
        return 'tend to';
    }
  }

  IconData get icon {
    switch (this) {
      case ReminderCategory.watering:
        return Icons.water_drop;
      case ReminderCategory.repotting:
        return Icons.yard;
      case ReminderCategory.cutting:
        return Icons.content_cut;
      case ReminderCategory.fertilize:
        return Icons.eco;
      case ReminderCategory.supportStems:
        return Icons.architecture;
      case ReminderCategory.checkSoil:
        return Icons.opacity;
      case ReminderCategory.other:
        return Icons.more_horiz;
    }
  }

  static ReminderCategory fromValue(String? value) {
    return ReminderCategory.values.firstWhere(
      (c) => c.value == value,
      orElse: () => ReminderCategory.other,
    );
  }
}

enum ReminderRepeat {
  never,
  daily,
  every2Days,
  weekly,
  biweekly,
  monthly,
}

extension ReminderRepeatX on ReminderRepeat {
  String get value {
    switch (this) {
      case ReminderRepeat.never:
        return 'never';
      case ReminderRepeat.daily:
        return 'daily';
      case ReminderRepeat.every2Days:
        return 'every_2_days';
      case ReminderRepeat.weekly:
        return 'weekly';
      case ReminderRepeat.biweekly:
        return 'biweekly';
      case ReminderRepeat.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case ReminderRepeat.never:
        return 'Never';
      case ReminderRepeat.daily:
        return 'Every Day';
      case ReminderRepeat.every2Days:
        return 'Every 2 Days';
      case ReminderRepeat.weekly:
        return 'Every Week';
      case ReminderRepeat.biweekly:
        return 'Every 2 Weeks';
      case ReminderRepeat.monthly:
        return 'Every Month';
    }
  }

  /// Returns the next occurrence after [from] for this repeat rule.
  /// Returns null for [ReminderRepeat.never].
  DateTime? nextAfter(DateTime from) {
    switch (this) {
      case ReminderRepeat.never:
        return null;
      case ReminderRepeat.daily:
        return from.add(const Duration(days: 1));
      case ReminderRepeat.every2Days:
        return from.add(const Duration(days: 2));
      case ReminderRepeat.weekly:
        return from.add(const Duration(days: 7));
      case ReminderRepeat.biweekly:
        return from.add(const Duration(days: 14));
      case ReminderRepeat.monthly:
        return DateTime(from.year, from.month + 1, from.day, from.hour, from.minute);
    }
  }

  static ReminderRepeat fromValue(String? value) {
    return ReminderRepeat.values.firstWhere(
      (r) => r.value == value,
      orElse: () => ReminderRepeat.never,
    );
  }
}

class ReminderModel {
  final String reminderId;
  final ReminderCategory category;
  final String plantName;
  final String? plantImageUrl;
  final String? waterAmount;
  final ReminderRepeat repeat;
  final DateTime startDate;
  final TimeOfDay notifyTime;
  final bool isCompleted;
  final bool isExpired;
  final String? fcmToken;
  final DateTime createdAt;

  ReminderModel({
    required this.reminderId,
    required this.category,
    required this.plantName,
    this.plantImageUrl,
    this.waterAmount,
    required this.repeat,
    required this.startDate,
    required this.notifyTime,
    this.isCompleted = false,
    this.isExpired = false,
    this.fcmToken,
    required this.createdAt,
  });

  /// Combine [startDate] (date part) with [notifyTime] into a single DateTime.
  DateTime get scheduledDateTime => DateTime(
        startDate.year,
        startDate.month,
        startDate.day,
        notifyTime.hour,
        notifyTime.minute,
      );

  /// Compute the next upcoming occurrence after [now] given the repeat rule.
  DateTime? nextOccurrenceAfter(DateTime now) {
    DateTime occ = scheduledDateTime;
    if (occ.isAfter(now)) return occ;
    if (repeat == ReminderRepeat.never) return null;
    while (!occ.isAfter(now)) {
      final next = repeat.nextAfter(occ);
      if (next == null) return null;
      occ = next;
    }
    return occ;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'reminderId': reminderId,
      'category': category.value,
      'plantName': plantName,
      'plantImageUrl': plantImageUrl,
      'waterAmount': waterAmount,
      'repeat': repeat.value,
      'startDate': Timestamp.fromDate(startDate),
      'notifyTime': '${notifyTime.hour.toString().padLeft(2, '0')}:${notifyTime.minute.toString().padLeft(2, '0')}',
      'isCompleted': isCompleted,
      'isExpired': isExpired,
      'fcmToken': fcmToken,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory ReminderModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final timeStr = (data['notifyTime'] as String?) ?? '08:00';
    final parts = timeStr.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    return ReminderModel(
      reminderId: doc.id,
      category: ReminderCategoryX.fromValue(data['category'] as String?),
      plantName: (data['plantName'] as String?) ?? 'Unknown plant',
      plantImageUrl: data['plantImageUrl'] as String?,
      waterAmount: data['waterAmount'] as String?,
      repeat: ReminderRepeatX.fromValue(data['repeat'] as String?),
      startDate: (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notifyTime: TimeOfDay(hour: hour, minute: minute),
      isCompleted: (data['isCompleted'] as bool?) ?? false,
      isExpired: (data['isExpired'] as bool?) ?? false,
      fcmToken: data['fcmToken'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  ReminderModel copyWith({
    ReminderCategory? category,
    String? plantName,
    String? plantImageUrl,
    String? waterAmount,
    ReminderRepeat? repeat,
    DateTime? startDate,
    TimeOfDay? notifyTime,
    bool? isCompleted,
    bool? isExpired,
    String? fcmToken,
  }) {
    return ReminderModel(
      reminderId: reminderId,
      category: category ?? this.category,
      plantName: plantName ?? this.plantName,
      plantImageUrl: plantImageUrl ?? this.plantImageUrl,
      waterAmount: waterAmount ?? this.waterAmount,
      repeat: repeat ?? this.repeat,
      startDate: startDate ?? this.startDate,
      notifyTime: notifyTime ?? this.notifyTime,
      isCompleted: isCompleted ?? this.isCompleted,
      isExpired: isExpired ?? this.isExpired,
      fcmToken: fcmToken ?? this.fcmToken,
      createdAt: createdAt,
    );
  }
}
