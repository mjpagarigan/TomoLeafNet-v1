import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'app_session.dart';
import 'models/scan_model.dart';
import 'services/chat_service.dart';
import 'services/firestore_service.dart';
import 'widgets/tomo_ui.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.tutorialInputKey});

  final GlobalKey? tutorialInputKey;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  final FirestoreService _firestoreService = FirestoreService();

  final List<ChatMessage> _messages = [];
  bool _isTyping = false;

  static const List<String> _suggestedQuestions = [
    "Why are my tomato leaves showing white trails?",
    "How do I treat Early Blight on my tomato plant?",
    "What does Leaf Mold look like?",
    "My plant looks healthy - how do I keep it that way?",
    "My confidence score was low - should I be worried?",
  ];

  @override
  void initState() {
    super.initState();
    _chatService.warmBackend();
  }

  bool get _isAuthenticated => FirebaseAuth.instance.currentUser != null;
  bool get _isGuest => AppSession.instance.isGuest;
  bool get _canChat => _isAuthenticated || _isGuest;

  Future<List<Map<String, dynamic>>> _fetchScanHistoryPayload() async {
    if (_isGuest) return const [];
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    try {
      final scans = await _firestoreService.getRecentScans(user.uid, limit: 5);
      return scans.map(_scanToPayload).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _scanToPayload(ScanModel scan) {
    return {
      'disease': scan.predictedDisease,
      'confidence': double.parse(
        (scan.confidenceScore * 100).toStringAsFixed(1),
      ),
      'confidenceLabel': scan.confidenceLabel.isNotEmpty
          ? scan.confidenceLabel
          : ScanModel.getConfidenceLabel(scan.confidenceScore),
      'scanType': scan.scanType,
      'timestamp': _relativeTime(scan.timestamp),
    };
  }

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m minute${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hour${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d day${d == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 30) {
      final w = (diff.inDays / 7).floor();
      return '$w week${w == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 365) {
      final mo = (diff.inDays / 30).floor();
      return '$mo month${mo == 1 ? '' : 's'} ago';
    }
    final y = (diff.inDays / 365).floor();
    return '$y year${y == 1 ? '' : 's'} ago';
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || !_canChat) return;

    final userMessage = ChatMessage(
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isTyping = true;
    });
    _textController.clear();
    _scrollToBottom();

    try {
      final history = _messages
          .skip(_messages.length > 10 ? _messages.length - 10 : 0)
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'text': m.text,
              })
          .toList();

      final scanHistory = await _fetchScanHistoryPayload();

      final reply = await _chatService.sendMessage(
        message: text.trim(),
        history: history,
        scanHistory: scanHistory,
      );

      setState(() {
        _messages.add(ChatMessage(
          text: reply,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: e.toString().replaceAll(RegExp(r'Exception: '), ''),
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isTyping = false;
      });
    }

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppSession>();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? TomoPalette.bg : const Color(0xFFF5F5F0),
      body: TomoBackdrop(
        isDark: isDark,
        child: SafeArea(
          child: _buildChat(theme, isDark),
        ),
      ),
    );
  }

  Widget _buildChat(ThemeData theme, bool isDark) {
    final badgeBgColor =
        isDark ? const Color(0xFF1F3025) : const Color(0xFFE8F3E5);
    final canPop = Navigator.of(context).canPop();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              if (canPop) ...[
                Container(
                  decoration: TomoDecorations.pill(isDark: isDark),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: isDark ? TomoPalette.text : TomoPalette.lightText,
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tomo',
                      style: GoogleFonts.dmSans(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color:
                            isDark ? TomoPalette.text : TomoPalette.lightText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Plant Health Assistant',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: isDark
                            ? TomoPalette.textMuted
                            : TomoPalette.lightTextSubtle,
                      ),
                    ),
                  ],
                ),
              ),
              if (_messages.isNotEmpty)
                Container(
                  decoration: TomoDecorations.pill(isDark: isDark),
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color:
                        isDark ? TomoPalette.textSubtle : TomoPalette.lightText,
                    onPressed: _clearChat,
                    tooltip: 'Clear chat',
                  ),
                ),
            ],
          ),
        ),
        if (_isGuest)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TomoGlassCard(
              isDark: isDark,
              radius: 16,
              color: isDark ? const Color(0x991F3025) : const Color(0xFFE8F3E5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text(
                'Guest mode: chat is available, but messages and scan context are not saved.',
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : const Color(0xFF206020),
                ),
              ),
            ),
          ),
        if (_messages.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Suggested questions:',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withAlpha(120),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedQuestions.map((q) {
                    return GestureDetector(
                      onTap: () => _sendMessage(q),
                      child: TomoGlassCard(
                        isDark: isDark,
                        radius: 16,
                        color: badgeBgColor.withOpacity(isDark ? 0.70 : 0.92),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Text(
                          q,
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF206020),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                TomoPalette.primaryBright,
                                TomoPalette.primaryDeep,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: TomoPalette.primary.withOpacity(0.25),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.eco,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          "Hi! I'm Tomo 🌿",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Your personal plant health assistant.\nAsk me anything about your tomato plants, recent scans, or how to treat leaf diseases.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            fontSize: 14,
                            height: 1.5,
                            color: theme.colorScheme.onSurface.withAlpha(140),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: _messages.length + (_isTyping ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length && _isTyping) {
                      return _buildTypingIndicator(isDark);
                    }
                    return _buildMessageBubble(_messages[index], isDark, theme);
                  },
                ),
        ),
        Container(
          key: widget.tutorialInputKey,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TomoGlassCard(
                        isDark: isDark,
                        radius: 24,
                        child: TextField(
                          controller: _textController,
                          style: GoogleFonts.dmSans(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Type your question...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: _sendMessage,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _sendMessage(_textController.text),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: TomoPalette.primary,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: TomoPalette.primary.withOpacity(0.4),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                if (MediaQuery.of(context).viewInsets.bottom == 0)
                  const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(
    ChatMessage message,
    bool isDark,
    ThemeData theme,
  ) {
    final isUser = message.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF3CB45A).withAlpha(40),
              child: const Icon(
                Icons.eco,
                size: 18,
                color: Color(0xFF3CB45A),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? TomoPalette.primary
                        : (isDark
                            ? const Color(0xE6131B17)
                            : const Color(0xF0FFFFFF)),
                    border: (!isUser && isDark)
                        ? Border.all(color: const Color(0x12FFFFFF))
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 18),
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        color:
                            isUser ? Colors.white : theme.colorScheme.onSurface,
                        height: 1.4,
                      ),
                      children: _parseMarkdown(
                        message.text,
                        GoogleFonts.dmSans(
                          fontSize: 14,
                          color: isUser
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(message.timestamp),
                  style: GoogleFonts.dmSans(
                    fontSize: 10,
                    color: theme.colorScheme.onSurface.withAlpha(80),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [TomoPalette.primaryBright, TomoPalette.primaryDeep],
              ),
            ),
            child: const Icon(Icons.eco, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xE6131B17) : const Color(0xF0FFFFFF),
              border:
                  isDark ? Border.all(color: const Color(0x12FFFFFF)) : null,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  List<TextSpan> _parseMarkdown(String text, TextStyle baseStyle) {
    final spans = <TextSpan>[];
    final boldItalicRegex = RegExp(r'\*\*\*(.+?)\*\*\*');
    final boldRegex = RegExp(r'\*\*(.+?)\*\*');
    final italicRegex = RegExp(r'\*(.+?)\*');
    final combined = RegExp(r'\*{1,3}(.+?)\*{1,3}');

    int cursor = 0;
    for (final match in combined.allMatches(text)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, match.start)));
      }
      final raw = match.group(0)!;
      final inner = match.group(1)!;

      if (boldItalicRegex.hasMatch(raw)) {
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(
            fontWeight: FontWeight.bold,
            fontStyle: FontStyle.italic,
          ),
        ));
      } else if (boldRegex.hasMatch(raw)) {
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (italicRegex.hasMatch(raw)) {
        spans.add(TextSpan(
          text: inner,
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else {
        spans.add(TextSpan(text: raw));
      }
      cursor = match.end;
    }

    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_controller.value - delay) % 1.0).clamp(0.0, 1.0);
            final y = -4.0 * (t < 0.5 ? t : 1.0 - t);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.translate(
                offset: Offset(0, y * 2),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3CB45A)
                        .withAlpha((150 + (t * 105)).toInt().clamp(0, 255)),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
