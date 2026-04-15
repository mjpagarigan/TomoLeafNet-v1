import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanRatingSection extends StatelessWidget {
  final String? selectedRating;
  final String? confirmationMessage;
  final bool enabled;
  final VoidCallback onThumbsUp;
  final VoidCallback onThumbsDown;

  const ScanRatingSection({
    super.key,
    required this.selectedRating,
    required this.confirmationMessage,
    required this.enabled,
    required this.onThumbsUp,
    required this.onThumbsDown,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasSelection = selectedRating != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Was this result accurate?',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _RatingButton(
                  icon: Icons.thumb_up_alt_rounded,
                  label: 'Yes',
                  color: const Color(0xFF309249),
                  isSelected: selectedRating == 'thumbs_up',
                  isDisabled: hasSelection || !enabled,
                  onTap: onThumbsUp,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _RatingButton(
                  icon: Icons.thumb_down_alt_rounded,
                  label: 'No',
                  color: Colors.redAccent,
                  isSelected: selectedRating == 'thumbs_down',
                  isDisabled: hasSelection || !enabled,
                  onTap: onThumbsDown,
                ),
              ),
            ],
          ),
          if (confirmationMessage != null) ...[
            const SizedBox(height: 14),
            Text(
              confirmationMessage!,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selectedRating == 'thumbs_up'
                    ? const Color(0xFF309249)
                    : Colors.redAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RatingButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _RatingButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isDisabled ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : color.withOpacity(0.25),
            width: isSelected ? 2 : 1.25,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : color.withOpacity(isDisabled ? 0.55 : 0.85),
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isSelected ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
