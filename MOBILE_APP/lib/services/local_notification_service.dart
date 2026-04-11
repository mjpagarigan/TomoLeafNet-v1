import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

import '../models/reminder_model.dart';

/// Wraps `flutter_local_notifications` and exposes the operations the
/// reminder system needs: initialise, schedule, cancel, request permission.
///
/// Notification IDs are derived from the Firestore reminder ID hash so that
/// each reminder maps to a stable, cancellable local notification.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  /// Callback fired when the user taps a notification. The Reminders screen
  /// can subscribe to this so it knows to navigate.
  void Function(String? payload)? onNotificationTap;

  Future<void> init() async {
    if (_initialised) return;

    tzdata.initializeTimeZones();
    try {
      final localName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localName));
    } catch (_) {
      // Fall back to UTC if the platform timezone can't be resolved.
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        onNotificationTap?.call(resp.payload);
      },
    );

    _initialised = true;
  }

  /// Request notification permissions. Android 13+ requires the runtime
  /// POST_NOTIFICATIONS prompt; iOS uses the standard alert dialog.
  Future<bool> requestPermissions() async {
    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? true;
    }
    return true;
  }

  /// Schedule a local notification for [reminder]. Cancels any existing
  /// notification for the same reminder first. Repeating reminders use the
  /// matching `DateTimeComponents` so the OS reschedules them automatically.
  Future<void> scheduleForReminder(ReminderModel reminder) async {
    await cancelForReminder(reminder.reminderId);

    final now = DateTime.now();
    final next = reminder.nextOccurrenceAfter(now);
    if (next == null) {
      // Already past and not repeating — nothing to schedule.
      return;
    }

    final tzScheduled = tz.TZDateTime.from(next, tz.local);
    final id = _idFor(reminder.reminderId);

    final title = '${reminder.category.label} Reminder';
    final body =
        'Time to ${reminder.category.verb} your ${reminder.plantName}';

    const androidDetails = AndroidNotificationDetails(
      'tomoleafnet_reminders',
      'Plant Care Reminders',
      channelDescription: 'Reminders for watering, pruning, and other plant care tasks.',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    final matchComponents = _matchComponentsFor(reminder.repeat);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzScheduled,
      details,
      payload: reminder.reminderId,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: matchComponents,
    );
  }

  Future<void> cancelForReminder(String reminderId) async {
    await _plugin.cancel(_idFor(reminderId));
  }

  Future<void> cancelAll() async => _plugin.cancelAll();

  /// Stable 31-bit int ID derived from the Firestore document ID.
  int _idFor(String reminderId) {
    return reminderId.hashCode & 0x7fffffff;
  }

  /// Map our [ReminderRepeat] enum to the OS-level recurrence rule.
  /// "every 2 days" / biweekly / monthly are not directly supported by
  /// `DateTimeComponents`, so they are scheduled as one-shot notifications;
  /// the backend FCM scheduler handles those cases reliably.
  DateTimeComponents? _matchComponentsFor(ReminderRepeat repeat) {
    switch (repeat) {
      case ReminderRepeat.never:
        return null;
      case ReminderRepeat.daily:
        return DateTimeComponents.time;
      case ReminderRepeat.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case ReminderRepeat.every2Days:
      case ReminderRepeat.biweekly:
      case ReminderRepeat.monthly:
        return null;
    }
  }
}
