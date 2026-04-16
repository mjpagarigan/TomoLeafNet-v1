import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../core/data/articles_data.dart';

class VideoArticleScreen extends StatefulWidget {
  final ArticleModel article;

  const VideoArticleScreen({super.key, required this.article});

  @override
  State<VideoArticleScreen> createState() => _VideoArticleScreenState();
}

class _VideoArticleScreenState extends State<VideoArticleScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _trackRead();
    _controller = VideoPlayerController.asset(widget.article.videoAsset!)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _isInitialized = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _hasError = true);
      });
    _controller.addListener(_onVideoTick);
  }

  void _onVideoTick() {
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    _controller.removeListener(_onVideoTick);
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const accent = Color(0xFF309249);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F0),
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
            aspectRatio: _isInitialized ? _controller.value.aspectRatio : 16 / 9,
            child: Container(
              color: Colors.black,
              child: _hasError
                  ? _buildError()
                  : !_isInitialized
                      ? const Center(
                          child: CircularProgressIndicator(color: accent),
                        )
                      : GestureDetector(
                          onTap: () =>
                              setState(() => _showControls = !_showControls),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_controller),
                              if (_showControls) _buildControls(),
                            ],
                          ),
                        ),
            ),
          ),
          if (_isInitialized && !_hasError)
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              colors: const VideoProgressColors(
                playedColor: accent,
                bufferedColor: Colors.white24,
                backgroundColor: Colors.white12,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    final pos = _controller.value.position;
    final dur = _controller.value.duration;
    return Container(
      color: Colors.black38,
      child: Stack(
        children: [
          Center(
            child: IconButton(
              iconSize: 64,
              icon: Icon(
                _controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
            ),
          ),
          Positioned(
            bottom: 8,
            right: 12,
            child: Text(
              '${_formatDuration(pos)} / ${_formatDuration(dur)}',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.white70),
          const SizedBox(height: 12),
          Text(
            'Unable to load video.',
            style: GoogleFonts.spaceGrotesk(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
