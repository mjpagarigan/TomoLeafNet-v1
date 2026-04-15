import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models/contribution_stats.dart';
import 'models/user_model.dart';
import 'services/firestore_service.dart';
import 'theme_provider.dart';
import 'services/auth_service.dart';
import 'widgets/onboarding_tutorial.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final user = FirebaseAuth.instance.currentUser;
    final firestoreService = FirestoreService();

    return Scaffold(
      appBar: AppBar(
        title: Text('More', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // --- User Profile Section ---
          if (user != null) ...[
            _buildSectionHeader('Profile', theme),
            const SizedBox(height: 12),
            _buildSettingsCard(
              theme: theme,
              isDark: isDark,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFF309249).withAlpha(40),
                        backgroundImage: user.photoURL != null
                            ? NetworkImage(user.photoURL!)
                            : null,
                        child: user.photoURL == null
                            ? Text(
                                (user.displayName ?? user.email ?? '?')[0].toUpperCase(),
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF309249),
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
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user.email ?? '',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withAlpha(120),
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

          if (user != null) ...[
            _buildSectionHeader('Manage Data Contributions', theme),
            const SizedBox(height: 12),
            StreamBuilder<UserModel?>(
              stream: firestoreService.getUserProfileStream(user.uid),
              builder: (context, userSnapshot) {
                final profile = userSnapshot.data;
                return StreamBuilder<ContributionStats>(
                  stream: firestoreService.getContributionStatsStream(user.uid),
                  builder: (context, statsSnapshot) {
                    final stats = statsSnapshot.data ?? const ContributionStats();
                    final contributionOptOut = profile?.contributionOptOut ?? false;

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
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _buildStatLine(theme, 'Images Contributed', stats.total),
                              _buildStatLine(theme, 'Approved', stats.approved),
                              _buildStatLine(theme, 'Pending Review', stats.pendingReview),
                              _buildStatLine(theme, 'Used in Training', stats.usedInTraining),
                            ],
                          ),
                        ),
                        Divider(
                          color: theme.colorScheme.onSurface.withAlpha(20),
                          height: 1,
                        ),
                        SwitchListTile(
                          value: contributionOptOut,
                          activeColor: const Color(0xFF309249),
                          title: Text(
                            'Opt Out of Future Contributions',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            contributionOptOut
                                ? 'We will stop asking you to donate future scans.'
                                : 'Allow the app to ask before donating high-quality scans.',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withAlpha(120),
                            ),
                          ),
                          onChanged: (value) =>
                              _setContributionOptOut(context, user.uid, value),
                        ),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          title: Text(
                            'Request Image Deletion',
                            style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            'Ask the admin review queue to remove your contributed images.',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withAlpha(120),
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

          // --- General Section (Tutorial) ---
          _buildSectionHeader('General', theme),
          const SizedBox(height: 12),
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              ListTile(
                leading: Icon(Icons.school_outlined,
                    color: const Color(0xFF309249), size: 24),
                title: Text('Show Tutorial Again',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    )),
                subtitle: Text('Replay the app walkthrough',
                    style: GoogleFonts.spaceGrotesk(
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
          _buildSettingsCard(
            theme: theme,
            isDark: isDark,
            children: [
              _buildInfoRow(theme, 'App Name', 'TomoLeafNet'),
              Divider(color: theme.colorScheme.onSurface.withAlpha(20), height: 1),
              _buildInfoRow(theme, 'Version', '1.0.0'),
              Divider(color: theme.colorScheme.onSurface.withAlpha(20), height: 1),
              _buildInfoRow(theme, 'Model', 'TomoLeafNet v4 MobileNetV3'),
              Divider(color: theme.colorScheme.onSurface.withAlpha(20), height: 1),
              _buildInfoRow(theme, 'Classes', '5 tomato leaf conditions'),
            ],
          ),

          // --- Sign Out ---
          if (user != null) ...[
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
                  style: GoogleFonts.spaceGrotesk(
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
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sign Out', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.spaceGrotesk()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.spaceGrotesk()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out', style: GoogleFonts.spaceGrotesk(color: Colors.redAccent)),
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
              : 'Contribution prompts enabled again.',
          style: GoogleFonts.spaceGrotesk(),
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
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Send a deletion request for all of your contributed images?',
          style: GoogleFonts.spaceGrotesk(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.spaceGrotesk()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Request',
              style: GoogleFonts.spaceGrotesk(color: Colors.redAccent),
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
          style: GoogleFonts.spaceGrotesk(),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Text(
      title,
      style: GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface.withAlpha(140),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildSettingsCard({
    required ThemeData theme,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 40 : 15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Text(
            '$value',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeRow(ThemeData theme, bool isDark, ThemeProvider themeProvider) {
    final mode = themeProvider.themeMode;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(
            isDark ? Icons.dark_mode : Icons.light_mode,
            color: const Color(0xFF13EC13),
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  mode == ThemeMode.system
                      ? 'System default'
                      : (mode == ThemeMode.dark ? 'Dark mode' : 'Light mode'),
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
              ],
            ),
          ),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android, size: 18)),
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 18)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 18)),
            ],
            selected: {mode},
            onSelectionChanged: (selected) {
              themeProvider.setThemeMode(selected.first);
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
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
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withAlpha(150),
            ),
          ),
          Text(
            value,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
