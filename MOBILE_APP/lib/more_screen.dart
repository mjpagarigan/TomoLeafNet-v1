import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'app_session.dart';
import 'models/contribution_stats.dart';
import 'models/user_model.dart';
import 'services/firestore_service.dart';
import 'theme_provider.dart';
import 'services/auth_service.dart';
import 'services/tflite_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'widgets/guided_onboarding_tutorial.dart';
import 'widgets/tomo_ui.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final session = Provider.of<AppSession>(context);
    final isGuest = session.isGuest;
    final user = FirebaseAuth.instance.currentUser;
    final firestoreService = FirestoreService();
    final tfliteService = TFLiteService();
    final modelSelectionFuture = tfliteService.initializeModelSelection();

    return Scaffold(
      backgroundColor: isDark ? TomoPalette.bg : TomoPalette.lightBg,
      body: TomoBackdrop(
        isDark: isDark,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              Text(
                'More',
                style: GoogleFonts.dmSans(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: isDark ? TomoPalette.text : TomoPalette.lightText,
                ),
              ),
              const SizedBox(height: 20),
              if (isGuest) ...[
                _buildSectionHeader('Guest Mode', theme),
                const SizedBox(height: 12),
                _buildSettingsCard(
                  theme: theme,
                  isDark: isDark,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'You are using TomoLeafNet as a guest.',
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Chat and camera-based scans work in this session, but history and cloud saving are disabled until you sign in.',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              height: 1.5,
                              color: theme.colorScheme.onSurface.withAlpha(140),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3CB45A),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Sign In',
                            style:
                                GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const RegisterScreen()),
                          ),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Create Account',
                            style:
                                GoogleFonts.dmSans(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              // --- User Profile Section ---
              if (user != null && !isGuest) ...[
                _buildSectionHeader('Profile', theme),
                const SizedBox(height: 12),
                _buildSettingsCard(
                  theme: theme,
                  isDark: isDark,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF4FC86C),
                                  Color(0xFF2F8D4A),
                                ],
                              ),
                              image: user.photoURL != null
                                  ? DecorationImage(
                                      image: NetworkImage(user.photoURL!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: user.photoURL == null
                                ? Text(
                                    (user.displayName ?? user.email ?? '?')[0]
                                        .toUpperCase(),
                                    style: GoogleFonts.dmSans(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.displayName ?? 'User',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user.email ?? '',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface
                                        .withAlpha(120),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
              ],

              if (user != null && !isGuest) ...[
                _buildSectionHeader('Manage Data Contributions', theme),
                const SizedBox(height: 12),
                StreamBuilder<UserModel?>(
                  stream: firestoreService.getUserProfileStream(user.uid),
                  builder: (context, userSnapshot) {
                    final profile = userSnapshot.data;
                    return StreamBuilder<ContributionStats>(
                      stream:
                          firestoreService.getContributionStatsStream(user.uid),
                      builder: (context, statsSnapshot) {
                        final stats =
                            statsSnapshot.data ?? const ContributionStats();
                        final contributionOptOut =
                            profile?.contributionOptOut ?? false;
                        final allowFutureContributions = !contributionOptOut;

                        return _buildSettingsCard(
                          theme: theme,
                          isDark: isDark,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your Contributions to TomoLeafNet',
                                    style: GoogleFonts.dmSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  _buildStatLine(
                                      theme, 'Images Contributed', stats.total),
                                  _buildStatLine(
                                      theme, 'Approved', stats.approved),
                                  _buildStatLine(theme, 'Pending Review',
                                      stats.pendingReview),
                                  _buildStatLine(theme, 'Used in Training',
                                      stats.usedInTraining),
                                ],
                              ),
                            ),
                            Divider(
                              color: theme.colorScheme.onSurface.withAlpha(20),
                              height: 1,
                            ),
                            SwitchListTile(
                              value: allowFutureContributions,
                              activeColor: const Color(0xFF3CB45A),
                              title: Text(
                                'Allow Future Contributions',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                allowFutureContributions
                                    ? 'Allow the app to ask before donating high-quality scans.'
                                    : 'We will stop asking you to donate future scans.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(120),
                                ),
                              ),
                              onChanged: (value) => _setContributionOptOut(
                                context,
                                user.uid,
                                !value,
                              ),
                            ),
                            ListTile(
                              leading: const Icon(Icons.delete_outline,
                                  color: Colors.redAccent),
                              title: Text(
                                'Request Image Deletion',
                                style: GoogleFonts.dmSans(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              subtitle: Text(
                                'Ask the admin review queue to remove your contributed images.',
                                style: GoogleFonts.dmSans(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurface
                                      .withAlpha(120),
                                ),
                              ),
                              onTap: stats.total == 0
                                  ? null
                                  : () => _requestContributionDeletion(
                                        context,
                                        firestoreService,
                                        user.uid,
                                      ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                const SizedBox(height: 28),
              ],

              // --- Appearance Section ---
              _buildSectionHeader('Appearance', theme),
              const SizedBox(height: 12),
              _buildSettingsCard(
                theme: theme,
                isDark: isDark,
                children: [
                  _buildThemeRow(theme, isDark, themeProvider),
                ],
              ),

              const SizedBox(height: 28),

              _buildSectionHeader('AI Model', theme),
              const SizedBox(height: 12),
              FutureBuilder<void>(
                future: modelSelectionFuture,
                builder: (context, snapshot) {
                  return ValueListenableBuilder<TFLiteModelSpec>(
                    valueListenable: TFLiteService.selectedModelListenable,
                    builder: (context, selectedModel, _) {
                      return _buildSettingsCard(
                        theme: theme,
                        isDark: isDark,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Choose the scan model',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'New Identify and Diagnose scans will use the model you pick here.',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: theme.colorScheme.onSurface
                                        .withAlpha(140),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Divider(
                            color: theme.colorScheme.onSurface.withAlpha(20),
                            height: 1,
                          ),
                          ...TFLiteService.availableModels.map(
                            (model) => _buildModelChoiceRow(
                              context: context,
                              theme: theme,
                              isDark: isDark,
                              model: model,
                              isSelected: selectedModel.id == model.id,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 28),

              // --- General Section (Tutorial) ---
              _buildSectionHeader('General', theme),
              const SizedBox(height: 12),
              _buildSettingsCard(
                theme: theme,
                isDark: isDark,
                children: [
                  ListTile(
                    leading: Icon(Icons.school_outlined,
                        color: const Color(0xFF3CB45A), size: 24),
                    title: Text('Show Tutorial Again',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface,
                        )),
                    subtitle: Text('Replay the app walkthrough',
                        style: GoogleFonts.dmSans(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withAlpha(120),
                        )),
                    trailing: Icon(Icons.chevron_right,
                        color: theme.colorScheme.onSurface.withAlpha(100)),
                    onTap: () => OnboardingTutorial.showTutorial(context),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // --- About Section ---
              _buildSectionHeader('About', theme),
              const SizedBox(height: 12),
              FutureBuilder<void>(
                future: modelSelectionFuture,
                builder: (context, snapshot) {
                  return ValueListenableBuilder<TFLiteModelSpec>(
                    valueListenable: TFLiteService.selectedModelListenable,
                    builder: (context, selectedModel, _) {
                      return _buildSettingsCard(
                        theme: theme,
                        isDark: isDark,
                        children: [
                          _buildInfoRow(theme, 'App Name', 'TomoLeafNet'),
                          Divider(
                              color: theme.colorScheme.onSurface.withAlpha(20),
                              height: 1),
                          _buildInfoRow(theme, 'Version', '1.0.0'),
                          Divider(
                              color: theme.colorScheme.onSurface.withAlpha(20),
                              height: 1),
                          _buildInfoRow(
                              theme, 'Active Model', selectedModel.displayName),
                          Divider(
                              color: theme.colorScheme.onSurface.withAlpha(20),
                              height: 1),
                          _buildInfoRow(
                              theme, 'Classes', '5 tomato leaf conditions'),
                          Divider(
                              color: theme.colorScheme.onSurface.withAlpha(20),
                              height: 1),
                          _buildClassDescriptions(theme, isDark),
                        ],
                      );
                    },
                  );
                },
              ),

              // --- Sign Out ---
              if (user != null && !isGuest) ...[
                const SizedBox(height: 28),
                _buildSectionHeader('Account', theme),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _signOut(context),
                    icon: const Icon(Icons.logout, size: 20),
                    label: Text(
                      'Sign Out',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ] else if (isGuest) ...[
                const SizedBox(height: 28),
                _buildSectionHeader('Guest Session', theme),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => AppSession.instance.setSignedOut(),
                    icon: const Icon(Icons.logout, size: 20),
                    label: Text(
                      'Exit Guest Mode',
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign Out',
            style: GoogleFonts.dmSans(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?',
            style: GoogleFonts.dmSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out',
                style: GoogleFonts.dmSans(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await AuthService().signOut();
    }
  }

  Future<void> _setContributionOptOut(
    BuildContext context,
    String uid,
    bool value,
  ) async {
    await FirestoreService().setContributionOptOut(uid, value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value
              ? 'Future contribution prompts disabled.'
              : 'Future contribution prompts enabled.',
          style: GoogleFonts.dmSans(),
        ),
      ),
    );
  }

  Future<void> _requestContributionDeletion(
    BuildContext context,
    FirestoreService firestoreService,
    String uid,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Request Image Deletion',
          style: GoogleFonts.dmSans(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Send a deletion request for all of your contributed images?',
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
              'Request',
              style: GoogleFonts.dmSans(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await firestoreService.requestContributionDeletion(uid);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Deletion request sent to the review queue.',
          style: GoogleFonts.dmSans(),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return TomoSectionLabel(title.toUpperCase(), isDark: isDark);
  }

  Widget _buildSettingsCard({
    required ThemeData theme,
    required bool isDark,
    required List<Widget> children,
  }) {
    return TomoGlassCard(
      isDark: isDark,
      radius: 24,
      child: Column(children: children),
    );
  }

  Widget _buildStatLine(ThemeData theme, String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Text(
            '$value',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeRow(
      ThemeData theme, bool isDark, ThemeProvider themeProvider) {
    final mode = themeProvider.themeMode;
    final segmentedButton = SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
            value: ThemeMode.system, icon: Icon(Icons.phone_android, size: 18)),
        ButtonSegment(
            value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
        ButtonSegment(
            value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
      ],
      selected: {mode},
      onSelectionChanged: (selected) {
        themeProvider.setThemeMode(selected.first);
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );

    final themeInfo = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Theme',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            mode == ThemeMode.system
                ? 'System default'
                : (mode == ThemeMode.dark ? 'Dark mode' : 'Light mode'),
            style: GoogleFonts.dmSans(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withAlpha(120),
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useCompactLayout = constraints.maxWidth < 430;

          if (useCompactLayout) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: const Color(0xFF3CB45A),
                      size: 24,
                    ),
                    const SizedBox(width: 14),
                    themeInfo,
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: segmentedButton,
                ),
              ],
            );
          }

          return Row(
            children: [
              Icon(
                isDark ? Icons.dark_mode : Icons.light_mode,
                color: const Color(0xFF3CB45A),
                size: 24,
              ),
              const SizedBox(width: 14),
              themeInfo,
              const SizedBox(width: 12),
              segmentedButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModelChoiceRow({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
    required TFLiteModelSpec model,
    required bool isSelected,
  }) {
    return ListTile(
      onTap: () => _selectModel(context, model),
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? const Color(0xFF3CB45A) : theme.iconTheme.color,
      ),
      title: Text(
        model.displayName,
        style: GoogleFonts.dmSans(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          model.description +
              (model.supportsHeatmap
                  ? ' Heatmap is available.'
                  : ' Heatmap is currently unavailable for this model.'),
          style: GoogleFonts.dmSans(
            fontSize: 12,
            height: 1.45,
            color: theme.colorScheme.onSurface.withAlpha(130),
          ),
        ),
      ),
      trailing: isSelected
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF3CB45A).withAlpha(40)
                    : const Color(0xFF3CB45A).withAlpha(24),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Current',
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3CB45A),
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _selectModel(
    BuildContext context,
    TFLiteModelSpec model,
  ) async {
    await TFLiteService().setActiveModel(model.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${model.displayName} will be used for new scans.',
          style: GoogleFonts.dmSans(),
        ),
      ),
    );
  }

  Widget _buildClassDescriptions(ThemeData theme, bool isDark) {
    final classDescriptions = const [
      {
        'title': 'Early Blight',
        'description':
            'A common fungal disease that starts as dark brown spots with target-like rings and can spread upward from older leaves.',
      },
      {
        'title': 'Leaf Mold',
        'description':
            'Usually appears in humid conditions, showing pale yellow patches on the upper leaf surface and olive-green mold underneath.',
      },
      {
        'title': 'Leaf Miner',
        'description':
            'Caused by insect larvae that tunnel inside the leaf, leaving winding white trails and weakening the plant over time.',
      },
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supported disease classes',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          ...classDescriptions.map(
            (item) => Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withAlpha(8)
                    : const Color(0xFF3CB45A).withAlpha(14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(14)
                      : const Color(0xFF3CB45A).withAlpha(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title']!,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['description']!,
                    style: GoogleFonts.dmSans(
                      fontSize: 12.5,
                      height: 1.45,
                      color: theme.colorScheme.onSurface.withAlpha(150),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
