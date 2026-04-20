import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/data/articles_data.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ArticleReaderScreen extends StatefulWidget {
  final ArticleModel article;

  const ArticleReaderScreen({super.key, required this.article});

  @override
  State<ArticleReaderScreen> createState() => _ArticleReaderScreenState();
}

class _ArticleReaderScreenState extends State<ArticleReaderScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();

    // Track read
    _trackArticleRead();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100 && _isLoading) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _hasError = false;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            setState(() {
              _isLoading = false;
              _hasError = true;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.article.url));
  }

  Future<void> _trackArticleRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // We use a URL-safe ID for the document key
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
      }
    } catch (e) {
      print("Failed to track article read: \$e");
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.article.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open external browser.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0A0F0C) : const Color(0xFFF5F5F0),
      appBar: AppBar(
        title: Text(
          widget.article.title,
          style: GoogleFonts.dmSans(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF131B17) : Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: 'Open in Browser',
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_hasError) WebViewWidget(controller: _controller),
          if (_isLoading && !_hasError)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(
                color: Color(0xFF3CB45A),
                backgroundColor: Colors.transparent,
              ),
            ),
          if (_hasError)
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.wifi_off, size: 64, color: Colors.grey[500]),
                  const SizedBox(height: 16),
                  Text(
                    "Unable to load article.\nPlease check your connection.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      color: isDark ? Colors.grey[400] : Colors.grey[700],
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      _controller.reload();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3CB45A),
                      foregroundColor: Colors.white,
                    ),
                    child: Text("Retry", style: GoogleFonts.dmSans()),
                  )
                ],
              ),
            ),
        ],
      ),
    );
  }
}
