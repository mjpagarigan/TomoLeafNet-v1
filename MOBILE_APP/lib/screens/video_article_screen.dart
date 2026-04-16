import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/data/articles_data.dart';

const _accent = Color(0xFF309249);

class VideoArticleScreen extends StatefulWidget {
  final ArticleModel article;

  const VideoArticleScreen({super.key, required this.article});

  @override
  State<VideoArticleScreen> createState() => _VideoArticleScreenState();
}

class _VideoArticleScreenState extends State<VideoArticleScreen> {
  @override
  void initState() {
    super.initState();
    _trackRead();
  }

  Future<void> _trackRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final safeId = widget.article.url.replaceAll(RegExp(r'[^\w\s]+'), '_');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('readArticles')
          .doc(safeId)
          .set({
        'title': widget.article.title,
        'url': widget.article.url,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  String? _youtubeThumbnailUrl() {
    final uri = Uri.tryParse(widget.article.url);
    if (uri == null) return null;

    String? videoId;
    if (uri.host.contains('youtu.be')) {
      final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
      if (segments.isNotEmpty) {
        videoId = segments.first;
      }
    } else if (uri.host.contains('youtube.com')) {
      videoId = uri.queryParameters['v'];
    }

    if (videoId == null || videoId.isEmpty) {
      return null;
    }

    return 'https://img.youtube.com/vi/$videoId/hqdefault.jpg';
  }

  Future<void> _openYouTube() async {
    final uri = Uri.tryParse(widget.article.url);
    if (uri == null) return;

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open YouTube right now.',
            style: GoogleFonts.spaceGrotesk(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final thumbnailUrl = _youtubeThumbnailUrl();

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          widget.article.title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        elevation: 1,
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailUrl != null)
                  Image.network(
                    thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      widget.article.coverImageUrl,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  Image.asset(
                    widget.article.coverImageUrl,
                    fit: BoxFit.cover,
                  ),
                Container(color: Colors.black.withOpacity(0.35)),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'YouTube',
                          style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _openYouTube,
                        style: FilledButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(
                          'Watch',
                          style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.article.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.article.source,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.article.summary,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      height: 1.5,
                      color: isDark ? Colors.grey[300] : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _openYouTube,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.smart_display_rounded),
                      label: Text(
                        'Open in YouTube',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
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
    );
  }
}
