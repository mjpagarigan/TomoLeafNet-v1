import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/reminder_model.dart';
import '../models/scan_model.dart';
import '../services/fcm_service.dart';
import '../services/firestore_service.dart';
import '../services/local_notification_service.dart';
import '../services/reminder_service.dart';
import '../services/reminders_backend.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen>
    with SingleTickerProviderStateMixin {
  final ReminderService _service = ReminderService();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _migrateOldPlantNames();
  }

  void _migrateOldPlantNames() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirestoreService().migrateReminderPlantNameToTomato(uid);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0F0C) : const Color(0xFFF5F5F0);
    const accent = Color(0xFF3CB45A);

    if (_uid == null) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(
          child: Text('Please sign in to view reminders.',
              style: GoogleFonts.dmSans()),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        const Icon(Icons.chevron_left, color: accent, size: 28),
                    label: Text(
                      'Back',
                      style: GoogleFonts.dmSans(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 16),
                    ),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  GestureDetector(
                    onTap: _showAddReminderSheet,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.add, color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Reminders',
                  style: GoogleFonts.dmSans(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131B17) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF2A2A2A)
                        : const Color(0xFFE8E8E8),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: isDark ? Colors.white : Colors.black87,
                  unselectedLabelColor:
                      isDark ? Colors.grey[500] : Colors.grey[600],
                  labelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.bold),
                  tabs: const [Tab(text: 'Today'), Tab(text: 'Upcoming')],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<List<ReminderModel>>(
                stream: _service.streamReminders(_uid!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final all = snapshot.data ?? const <ReminderModel>[];
                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _TodayTab(reminders: all, service: _service, uid: _uid!),
                      _UpcomingTab(reminders: all),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddReminderSheet() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final category = await showModalBottomSheet<ReminderCategory>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Which type of reminder would you like to set?',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 15,
                color: isDark ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 20),
            ...[
              ReminderCategory.watering,
              ReminderCategory.repotting,
              ReminderCategory.cutting,
              ReminderCategory.fertilize,
              ReminderCategory.other,
            ].map((c) => _categoryRow(ctx, c, isDark)),
            const Divider(height: 1),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: GoogleFonts.dmSans(
                  color: const Color(0xFF3CB45A),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (category != null && mounted) {
      await showReminderEditorSheet(
        context: context,
        category: category,
        existing: null,
      );
    }
  }

  Widget _categoryRow(BuildContext ctx, ReminderCategory c, bool isDark) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, c),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? Colors.grey[800]! : Colors.grey[200]!,
            ),
          ),
        ),
        child: Text(
          c.label,
          style: GoogleFonts.dmSans(
            color: const Color(0xFF3CB45A),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─── Today Tab ────────────────────────────────────────────────────────

class _TodayTab extends StatelessWidget {
  final List<ReminderModel> reminders;
  final ReminderService service;
  final String uid;

  const _TodayTab({
    required this.reminders,
    required this.service,
    required this.uid,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Filter reminders that have an occurrence today.
    final todayReminders = reminders.where((r) {
      // Single non-repeating: matches if startDate is today
      if (r.repeat == ReminderRepeat.never) {
        final s = r.startDate;
        return s.year == today.year &&
            s.month == today.month &&
            s.day == today.day;
      }
      // Repeating: today is within the schedule if startDate <= today and the
      // recurrence rule lands on today
      if (r.startDate.isAfter(today.add(const Duration(days: 1)))) return false;
      return _occursOn(r, today);
    }).toList();

    if (todayReminders.isEmpty) {
      return _EmptyState(
        icon: Icons.event_available,
        title: 'No reminders today',
        subtitle: 'Tap the + button to add your first plant care reminder.',
      );
    }

    // Group by category in display order
    final order = const [
      ReminderCategory.watering,
      ReminderCategory.repotting,
      ReminderCategory.cutting,
      ReminderCategory.fertilize,
      ReminderCategory.supportStems,
      ReminderCategory.checkSoil,
      ReminderCategory.other,
    ];

    final grouped = <ReminderCategory, List<ReminderModel>>{};
    for (final r in todayReminders) {
      grouped.putIfAbsent(r.category, () => []).add(r);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        for (final cat in order)
          if (grouped[cat] != null)
            _CategorySection(
              category: cat,
              reminders: grouped[cat]!,
              service: service,
              uid: uid,
              showCheckbox: true,
            ),
      ],
    );
  }

  bool _occursOn(ReminderModel r, DateTime day) {
    DateTime cursor = DateTime(
      r.startDate.year,
      r.startDate.month,
      r.startDate.day,
    );
    final dayEnd = day.add(const Duration(days: 1));
    while (cursor.isBefore(dayEnd)) {
      if (cursor.year == day.year &&
          cursor.month == day.month &&
          cursor.day == day.day) {
        return true;
      }
      final next = r.repeat.nextAfter(cursor);
      if (next == null) return false;
      cursor = DateTime(next.year, next.month, next.day);
      if (cursor.isAtSameMomentAs(dayEnd) || cursor.isAfter(dayEnd)) {
        return cursor.year == day.year &&
            cursor.month == day.month &&
            cursor.day == day.day;
      }
    }
    return false;
  }
}

// ─── Upcoming Tab ─────────────────────────────────────────────────────

class _UpcomingTab extends StatelessWidget {
  final List<ReminderModel> reminders;

  const _UpcomingTab({required this.reminders});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tomorrow =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));

    // Build a flat list of (date, reminder) up to 14 days ahead.
    final entries = <_UpcomingEntry>[];
    final horizon = tomorrow.add(const Duration(days: 14));
    for (final r in reminders) {
      DateTime cursor = DateTime(
        r.startDate.year,
        r.startDate.month,
        r.startDate.day,
        r.notifyTime.hour,
        r.notifyTime.minute,
      );
      // Walk forward until we land in the [tomorrow, horizon) window.
      var safety = 200;
      while (safety-- > 0 && cursor.isBefore(horizon)) {
        final dayOnly = DateTime(cursor.year, cursor.month, cursor.day);
        if (!dayOnly.isBefore(tomorrow)) {
          entries.add(_UpcomingEntry(date: dayOnly, reminder: r));
        }
        final next = r.repeat.nextAfter(cursor);
        if (next == null) break;
        cursor = next;
      }
    }

    if (entries.isEmpty) {
      return _EmptyState(
        icon: Icons.calendar_month,
        title: 'Nothing upcoming',
        subtitle: 'Reminders scheduled for future dates will appear here.',
      );
    }

    entries.sort((a, b) => a.date.compareTo(b.date));

    // Group by date
    final byDate = <DateTime, List<ReminderModel>>{};
    for (final e in entries) {
      byDate.putIfAbsent(e.date, () => []).add(e.reminder);
    }

    final sortedDates = byDate.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        for (final date in sortedDates) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
            child: Text(
              DateFormat('EEE, MMMM d').format(date),
              style: GoogleFonts.dmSans(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black87,
              ),
            ),
          ),
          for (final r in byDate[date]!)
            _UpcomingCard(category: r.category, reminder: r),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _UpcomingEntry {
  final DateTime date;
  final ReminderModel reminder;
  _UpcomingEntry({required this.date, required this.reminder});
}

// ─── Section + Card widgets ──────────────────────────────────────────

class _CategorySection extends StatelessWidget {
  final ReminderCategory category;
  final List<ReminderModel> reminders;
  final ReminderService service;
  final String uid;
  final bool showCheckbox;

  const _CategorySection({
    required this.category,
    required this.reminders,
    required this.service,
    required this.uid,
    required this.showCheckbox,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF131B17) : Colors.white;
    const accent = Color(0xFF3CB45A);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(category.icon, color: accent, size: 22),
                const SizedBox(width: 10),
                Text(
                  category.label.toUpperCase(),
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final r in reminders)
              _TodayCard(
                reminder: r,
                service: service,
                uid: uid,
                showCheckbox: showCheckbox,
              ),
          ],
        ),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  final ReminderModel reminder;
  final ReminderService service;
  final String uid;
  final bool showCheckbox;

  const _TodayCard({
    required this.reminder,
    required this.service,
    required this.uid,
    required this.showCheckbox,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final scheduledToday = DateTime(
      now.year,
      now.month,
      now.day,
      reminder.notifyTime.hour,
      reminder.notifyTime.minute,
    );
    final isExpired = scheduledToday.isBefore(now) && !reminder.isCompleted;

    return InkWell(
      onTap: () => showReminderEditorSheet(
        context: context,
        category: reminder.category,
        existing: reminder,
      ),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Opacity(
          opacity: reminder.isCompleted ? 0.5 : 1.0,
          child: Row(
            children: [
              _PlantThumb(imageUrl: reminder.plantImageUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.plantName,
                      style: GoogleFonts.dmSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isExpired
                          ? 'Expired'
                          : '${reminder.notifyTime.hour.toString().padLeft(2, '0')}:${reminder.notifyTime.minute.toString().padLeft(2, '0')}',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isExpired
                            ? Colors.red
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                onSelected: (value) async {
                  if (value == 'edit') {
                    await showReminderEditorSheet(
                      context: context,
                      category: reminder.category,
                      existing: reminder,
                    );
                    return;
                  }

                  await _deleteReminderWithConfirmation(context, reminder);
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(
                      'Edit reminder',
                      style: GoogleFonts.dmSans(),
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Text(
                      'Delete reminder',
                      style: GoogleFonts.dmSans(color: Colors.red),
                    ),
                  ),
                ],
              ),
              if (showCheckbox)
                GestureDetector(
                  onTap: () async {
                    await service.markCompleted(
                        uid, reminder.reminderId, !reminder.isCompleted);
                  },
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? Colors.grey[500]! : Colors.grey[400]!,
                        width: 2,
                      ),
                      color: reminder.isCompleted
                          ? const Color(0xFF3CB45A)
                          : Colors.transparent,
                    ),
                    child: reminder.isCompleted
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  final ReminderCategory category;
  final ReminderModel reminder;

  const _UpcomingCard({
    required this.category,
    required this.reminder,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? const Color(0xFF131B17) : Colors.white;
    const accent = Color(0xFF3CB45A);

    return InkWell(
      onTap: () => showReminderEditorSheet(
        context: context,
        category: reminder.category,
        existing: reminder,
      ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(category.icon, color: accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category.label.toUpperCase(),
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await showReminderEditorSheet(
                        context: context,
                        category: reminder.category,
                        existing: reminder,
                      );
                      return;
                    }

                    await _deleteReminderWithConfirmation(context, reminder);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Text(
                        'Edit reminder',
                        style: GoogleFonts.dmSans(),
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Text(
                        'Delete reminder',
                        style: GoogleFonts.dmSans(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _PlantThumb(imageUrl: reminder.plantImageUrl),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.plantName,
                        style: GoogleFonts.dmSans(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${reminder.notifyTime.hour.toString().padLeft(2, '0')}:${reminder.notifyTime.minute.toString().padLeft(2, '0')}',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlantThumb extends StatelessWidget {
  final String? imageUrl;
  const _PlantThumb({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholder = Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(Icons.local_florist,
          color: isDark ? Colors.grey[600] : Colors.grey[400], size: 28),
    );

    if (imageUrl == null || imageUrl!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: isDark ? Colors.grey[700] : Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                color: isDark ? Colors.grey[500] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Editor sheet (Add / Edit) ────────────────────────────────────────

Future<bool> _deleteReminderWithConfirmation(
  BuildContext context,
  ReminderModel reminder,
) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete reminder?', style: GoogleFonts.dmSans()),
      content: Text(
        'This action cannot be undone.',
        style: GoogleFonts.dmSans(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: GoogleFonts.dmSans()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete',
            style: GoogleFonts.dmSans(color: Colors.red),
          ),
        ),
      ],
    ),
  );

  if (confirmed != true) return false;

  await ReminderService().deleteReminder(uid, reminder.reminderId);
  await LocalNotificationService.instance
      .cancelForReminder(reminder.reminderId);
  await RemindersBackend.instance.cancel(
    uid: uid,
    reminderId: reminder.reminderId,
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Reminder deleted.',
          style: GoogleFonts.dmSans(),
        ),
      ),
    );
  }

  return true;
}

Future<bool> showReminderEditorSheet({
  required BuildContext context,
  required ReminderCategory category,
  ReminderModel? existing,
  String? initialPlantName,
  String? initialPlantImageUrl,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderEditorSheet(
      category: category,
      existing: existing,
      initialPlantName: initialPlantName,
      initialPlantImageUrl: initialPlantImageUrl,
    ),
  );

  final saved = result == true;
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                existing == null ? 'Reminder added.' : 'Reminder updated.',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF3CB45A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  return saved;
}

class _ReminderEditorSheet extends StatefulWidget {
  final ReminderCategory category;
  final ReminderModel? existing;
  final String? initialPlantName;
  final String? initialPlantImageUrl;

  const _ReminderEditorSheet({
    required this.category,
    this.existing,
    this.initialPlantName,
    this.initialPlantImageUrl,
  });

  @override
  State<_ReminderEditorSheet> createState() => _ReminderEditorSheetState();
}

class _ReminderEditorSheetState extends State<_ReminderEditorSheet> {
  final ReminderService _service = ReminderService();

  late String _plantName;
  String? _plantImageUrl;
  late String _waterAmount;
  late ReminderRepeat _repeat;
  late DateTime _startDate;
  late TimeOfDay _notifyTime;
  String? _timeValidationError;
  bool _isSaving = false;

  static const List<String> _waterOptions = [
    '1 cup',
    '2 cups',
    '500 ml',
    '1 L'
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _plantName = e?.plantName ?? widget.initialPlantName ?? 'Tomato';
    _plantImageUrl = e?.plantImageUrl ?? widget.initialPlantImageUrl;
    _waterAmount = e?.waterAmount ?? '1 cup';
    _repeat = e?.repeat ?? ReminderRepeat.every2Days;
    _startDate = e?.startDate ?? DateTime.now();
    _notifyTime = e?.notifyTime ?? const TimeOfDay(hour: 10, minute: 30);
    _validateDateTime();

    if (e == null && widget.initialPlantName == null) {
      _loadLatestScanAsDefault();
    }
  }

  Future<void> _loadLatestScanAsDefault() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('scans')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty || !mounted) return;
      final latest = ScanModel.fromFirestore(snap.docs.first);
      setState(() {
        _plantName = latest.predictedDisease;
        _plantImageUrl = latest.imageUrl;
      });
    } catch (_) {
      // Keep the 'Tomato' fallback if the fetch fails.
    }
  }

  void _validateDateTime() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay =
        DateTime(_startDate.year, _startDate.month, _startDate.day);

    if (selectedDay.isAtSameMomentAs(today)) {
      final selectedTime = DateTime(
        now.year,
        now.month,
        now.day,
        _notifyTime.hour,
        _notifyTime.minute,
      );
      if (selectedTime.isBefore(now)) {
        _timeValidationError =
            "Please choose a future time for today's reminder.";
        return;
      }
    }
    _timeValidationError = null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF131B17) : Colors.white;
    final fieldBg = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF1F1F1);
    const accent = Color(0xFF3CB45A);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.dmSans(
                            color: accent,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          widget.category.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: (_timeValidationError == null && !_isSaving)
                          ? _onSave
                          : null,
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: accent,
                              ),
                            )
                          : Text(
                              'Done',
                              style: GoogleFonts.dmSans(
                                  color: _timeValidationError == null
                                      ? accent
                                      : Colors.grey,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _field(
                        fieldBg,
                        isDark,
                        leading: null,
                        label: 'Plant',
                        trailing: Text(
                          _plantName,
                          style: GoogleFonts.dmSans(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        onTap: _pickPlant,
                      ),
                      const SizedBox(height: 12),
                      if (widget.category == ReminderCategory.watering) ...[
                        _field(
                          fieldBg,
                          isDark,
                          leading: const Icon(Icons.water_drop,
                              color: Colors.white70),
                          label: 'Water amount',
                          trailing: Text(
                            _waterAmount,
                            style: GoogleFonts.dmSans(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: _pickWaterAmount,
                        ),
                        const SizedBox(height: 12),
                      ],
                      _field(
                        fieldBg,
                        isDark,
                        leading:
                            const Icon(Icons.repeat, color: Colors.white70),
                        label: 'Repeat',
                        trailing: Text(
                          _repeat.label,
                          style: GoogleFonts.dmSans(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _pickRepeat,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        fieldBg,
                        isDark,
                        leading: const Icon(Icons.calendar_today,
                            color: Colors.white70),
                        label: 'Start Day',
                        trailing: Text(
                          DateFormat('d MMMM').format(_startDate),
                          style: GoogleFonts.dmSans(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _pickStartDate,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
                        child: Text(
                          'Choose the date of the first action',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _field(
                        fieldBg,
                        isDark,
                        leading: const Icon(Icons.notifications,
                            color: Colors.white70),
                        label: 'Notify',
                        trailing: Text(
                          '${_notifyTime.hour.toString().padLeft(2, '0')}:${_notifyTime.minute.toString().padLeft(2, '0')}',
                          style: GoogleFonts.dmSans(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _pickNotifyTime,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 6, 0, 0),
                        child: Text(
                          'Choose the time for notification',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ),
                      if (_timeValidationError != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: Colors.redAccent, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _timeValidationError!,
                                  style: GoogleFonts.dmSans(
                                    fontSize: 12,
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (widget.existing != null)
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: _onDelete,
                            style: TextButton.styleFrom(
                              backgroundColor: fieldBg,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Text(
                              'Delete Reminder',
                              style: GoogleFonts.dmSans(
                                color: Colors.red,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    Color bgColor,
    bool isDark, {
    Widget? leading,
    required String label,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            if (leading != null) ...[
              IconTheme(
                data: IconThemeData(
                    color: isDark ? Colors.white70 : Colors.grey[700],
                    size: 22),
                child: leading,
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Future<void> _pickPlant() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('scans')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .get();
    final scans = snapshot.docs.map(ScanModel.fromFirestore).toList();

    if (!mounted) return;
    final picked = await showModalBottomSheet<_PickedPlant>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose plant',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              onTap: () => Navigator.pop(
                ctx,
                const _PickedPlant('Tomato', null),
              ),
              leading:
                  const Icon(Icons.local_florist, color: Color(0xFF3CB45A)),
              title: Text(
                'Tomato',
                style: GoogleFonts.dmSans(
                    color: isDark ? Colors.white : Colors.black87),
              ),
              subtitle: Text('Default tomato plant',
                  style: GoogleFonts.dmSans(
                      color: isDark ? Colors.grey[500] : Colors.grey[600])),
            ),
            if (scans.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'From your recent scans',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: isDark ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: scans.map((s) {
                    return ListTile(
                      onTap: () => Navigator.pop(
                        ctx,
                        _PickedPlant(s.predictedDisease, s.imageUrl),
                      ),
                      leading: s.imageUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: s.imageUrl!,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.local_florist),
                              ),
                            )
                          : const Icon(Icons.local_florist),
                      title: Text(
                        s.predictedDisease,
                        style: GoogleFonts.dmSans(
                            color: isDark ? Colors.white : Colors.black87),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        _plantName = picked.name;
        _plantImageUrl = picked.imageUrl;
      });
    }
  }

  Future<void> _pickWaterAmount() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: _waterOptions
              .map(
                (opt) => ListTile(
                  onTap: () => Navigator.pop(ctx, opt),
                  title: Text(
                    opt,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      color: const Color(0xFF3CB45A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _waterAmount = picked);
  }

  Future<void> _pickRepeat() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showModalBottomSheet<ReminderRepeat>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131B17) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: ReminderRepeat.values
              .map((r) => ListTile(
                    onTap: () => Navigator.pop(ctx, r),
                    title: Text(
                      r.label,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.dmSans(
                        color: const Color(0xFF3CB45A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => _repeat = picked);
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _startDate.isBefore(today) ? today : _startDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _validateDateTime();
      });
    }
  }

  Future<void> _pickNotifyTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _notifyTime,
    );
    if (picked != null) {
      setState(() {
        _notifyTime = picked;
        _validateDateTime();
      });
    }
  }

  Future<void> _onSave() async {
    if (_isSaving) return;
    _validateDateTime();
    if (_timeValidationError != null) {
      setState(() {});
      return;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSaving = true);

    final fcmToken = await FcmService.instance.ensureToken();

    ReminderModel saved;
    try {
      if (widget.existing == null) {
        saved = await _service.createReminder(
          uid: uid,
          category: widget.category,
          plantName: _plantName,
          plantImageUrl: _plantImageUrl,
          waterAmount: widget.category == ReminderCategory.watering
              ? _waterAmount
              : null,
          repeat: _repeat,
          startDate: _startDate,
          notifyTime: _notifyTime,
          fcmToken: fcmToken,
        );
        if (fcmToken != null) {
          await RemindersBackend.instance
              .schedule(uid: uid, fcmToken: fcmToken, reminder: saved);
        }
      } else {
        saved = widget.existing!.copyWith(
          plantName: _plantName,
          plantImageUrl: _plantImageUrl,
          waterAmount: widget.category == ReminderCategory.watering
              ? _waterAmount
              : null,
          repeat: _repeat,
          startDate: _startDate,
          notifyTime: _notifyTime,
          fcmToken: fcmToken,
          isCompleted: false,
          isExpired: false,
        );
        await _service.updateReminder(uid, saved);
        if (fcmToken != null) {
          await RemindersBackend.instance
              .update(uid: uid, fcmToken: fcmToken, reminder: saved);
        }
      }
    } on ReminderBackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message, style: GoogleFonts.dmSans()),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isSaving = false);
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to save reminder right now.',
              style: GoogleFonts.dmSans(),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isSaving = false);
      }
      return;
    }

    try {
      await LocalNotificationService.instance.scheduleForReminder(saved);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reminder saved, but local notification scheduling failed.',
              style: GoogleFonts.dmSans(),
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }

    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _onDelete() async {
    final existing = widget.existing;
    if (existing == null) return;

    final deleted = await _deleteReminderWithConfirmation(context, existing);
    if (deleted && mounted) Navigator.pop(context);
  }
}

class _PickedPlant {
  final String name;
  final String? imageUrl;
  const _PickedPlant(this.name, this.imageUrl);
}
