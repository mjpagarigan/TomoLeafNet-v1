import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../core/data/articles_data.dart';

const _accent = Color(0xFF309249);

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
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openFullScreen() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) =>
            _FullScreenVideoScreen(controller: _controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            aspectRatio:
                _isInitialized ? _controller.value.aspectRatio : 16 / 9,
            child: Container(
              color: Colors.black,
              child: _hasError
                  ? const _PlayerError()
                  : !_isInitialized
                      ? const Center(
                          child:
                              CircularProgressIndicator(color: _accent),
                        )
                      : _PlayerView(
                          controller: _controller,
                          isFullScreen: false,
                          onFullScreenToggle: _openFullScreen,
                        ),
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
}

/// Reusable player surface: video + tap-to-toggle overlay with auto-hide.
/// Used both inline in the article screen and inside the fullscreen screen.
class _PlayerView extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isFullScreen;
  final VoidCallback? onFullScreenToggle;

  const _PlayerView({
    required this.controller,
    required this.isFullScreen,
    this.onFullScreenToggle,
  });

  @override
  State<_PlayerView> createState() => _PlayerViewState();
}

class _PlayerViewState extends State<_PlayerView> {
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (widget.controller.value.isPlaying) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _togglePlay() {
    final c = widget.controller;
    if (c.value.isPlaying) {
      c.pause();
      _hideTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      c.play();
      _scheduleHide();
      setState(() {});
    }
  }

  void _seekBy(Duration delta) {
    final v = widget.controller.value;
    final target = v.position + delta;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > v.duration ? v.duration : target);
    widget.controller.seekTo(clamped);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      fit: StackFit.expand,
      children: [
        VideoPlayer(widget.controller),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: AnimatedOpacity(
              opacity: _showControls ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _ControlsOverlay(
                  controller: widget.controller,
                  isFullScreen: widget.isFullScreen,
                  onPlayPause: _togglePlay,
                  onSeekBy: _seekBy,
                  onFullScreenToggle: widget.onFullScreenToggle,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  final bool isFullScreen;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeekBy;
  final VoidCallback? onFullScreenToggle;

  const _ControlsOverlay({
    required this.controller,
    required this.isFullScreen,
    required this.onPlayPause,
    required this.onSeekBy,
    this.onFullScreenToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: Stack(
        children: [
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SeekButton(
                  icon: Icons.replay_10_rounded,
                  onPressed: () =>
                      onSeekBy(const Duration(seconds: -10)),
                ),
                const SizedBox(width: 20),
                _PlayPauseButton(
                  controller: controller,
                  onTap: onPlayPause,
                ),
                const SizedBox(width: 20),
                _SeekButton(
                  icon: Icons.forward_10_rounded,
                  onPressed: () =>
                      onSeekBy(const Duration(seconds: 10)),
                ),
              ],
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  colors: const VideoProgressColors(
                    playedColor: _accent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const SizedBox(width: 4),
                    _TimeLabel(controller: controller, showDuration: false),
                    const Text(
                      '  /  ',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    _TimeLabel(controller: controller, showDuration: true),
                    const Spacer(),
                    if (onFullScreenToggle != null)
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 40, minHeight: 40),
                        icon: Icon(
                          isFullScreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: onFullScreenToggle,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _SeekButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      iconSize: 40,
      icon: Icon(icon, color: Colors.white),
      onPressed: onPressed,
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final VideoPlayerController controller;
  final VoidCallback onTap;

  const _PlayPauseButton({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: const BoxDecoration(
          color: Colors.black54,
          shape: BoxShape.circle,
        ),
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (_, value, __) => Icon(
            value.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 48,
          ),
        ),
      ),
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final VideoPlayerController controller;
  final bool showDuration;

  const _TimeLabel({
    required this.controller,
    required this.showDuration,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final d = showDuration ? value.duration : value.position;
        return Text(
          _fmt(d),
          style: GoogleFonts.spaceGrotesk(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }
}

class _FullScreenVideoScreen extends StatefulWidget {
  final VideoPlayerController controller;

  const _FullScreenVideoScreen({required this.controller});

  @override
  State<_FullScreenVideoScreen> createState() =>
      _FullScreenVideoScreenState();
}

class _FullScreenVideoScreenState extends State<_FullScreenVideoScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AspectRatio(
          aspectRatio: widget.controller.value.aspectRatio,
          child: _PlayerView(
            controller: widget.controller,
            isFullScreen: true,
            onFullScreenToggle: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError();

  @override
  Widget build(BuildContext context) {
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
