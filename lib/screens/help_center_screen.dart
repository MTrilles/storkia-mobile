import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';

typedef JsonMap = Map<String, dynamic>;

class HelpCenterScreen extends StatefulWidget {
  final String baseUrl;
  final String token;

  const HelpCenterScreen({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen>
    with WidgetsBindingObserver {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _pollTimer;

  bool _isLoading = true;
  bool _isSending = false;
  String _conversationStatus = 'open';
  List<JsonMap> _messages = [];
  XFile? _attachment;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchMessages();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchMessages(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchMessages(silent: true);
    }
  }

  Future<void> _fetchMessages({bool silent = false}) async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/help-center/messages'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted || response.statusCode != 200) return;
      final body = json.decode(response.body);
      List<dynamic> rawList = [];
      String status = _conversationStatus;

      if (body is Map) {
        final d = body['data'] ?? body;
        if (d is List) {
          rawList = d;
        } else if (d is Map) {
          final nested = d['messages'] ?? d['items'] ?? d['data'];
          if (nested is List) {
            rawList = nested;
          }
          if (d['conversation'] is Map && d['conversation']['status'] != null) {
            status = d['conversation']['status'].toString();
          } else if (d['status'] is String) {
            status = d['status'].toString();
          }
        }
      }

      final List<JsonMap> parsed = [
        for (final m in rawList)
          if (m is Map) Map<String, dynamic>.from(m),
      ];
      final bool hadNew = parsed.length != _messages.length;

      setState(() {
        _messages = parsed;
        _conversationStatus = status;
        _isLoading = false;
      });

      if (hadNew) {
        _scrollToBottom();
        _markAsRead();
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _markAsRead() async {
    try {
      await http.patch(
        Uri.parse('$_domain/api/v1/help-center/read'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() => _attachment = picked);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if ((text.isEmpty && _attachment == null) || _isSending) return;

    setState(() => _isSending = true);
    final XFile? fileToSend = _attachment;
    _msgController.clear();
    setState(() => _attachment = null);

    try {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/help-center/messages'),
      );
      req.headers['Authorization'] = 'Bearer ${widget.token}';
      req.headers['Accept'] = 'application/json';
      req.fields['message'] = text.isNotEmpty ? text : 'Sent an attachment';
      if (fileToSend != null) {
        req.files.add(
          await http.MultipartFile.fromPath('attachment', fileToSend.path),
        );
      }

      final streamed = await req.send().timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (response.statusCode == 200 || response.statusCode == 201) {
        await _fetchMessages(silent: true);
        _scrollToBottom();
      } else {
        _msgController.text = text;
      }
    } catch (_) {
      _msgController.text = text;
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: StorkTheme.brandGradient,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(
                Icons.support_agent_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Storkia Help Center',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: StorkTheme.success,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          'Direct Support Thread • ${_conversationStatus.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: StorkTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : _messages.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 74,
                                height: 74,
                                decoration: BoxDecoration(
                                  color:
                                      StorkTheme.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.support_agent_rounded,
                                  size: 38,
                                  color: StorkTheme.primary,
                                ),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'How can Storkia Support help you?',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Send us a message below regarding orders, E-Wallet top-ups, refunds, or account inquiries.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: StorkTheme.textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
                          final String senderType = (m['sender_type'] ?? 'user')
                              .toString()
                              .toLowerCase();
                          final bool isMe = senderType != 'admin';
                          final String text = m['message']?.toString() ?? '';
                          final String? attachmentUrl =
                              m['attachment_url']?.toString() ??
                                  (m['attachment_path'] != null
                                      ? ApiConfig.storageUrl(
                                          m['attachment_path'].toString(),
                                          _domain,
                                        )
                                      : null);

                          return Align(
                            alignment: isMe
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 11),
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.sizeOf(context).width * 0.76,
                              ),
                              decoration: BoxDecoration(
                                gradient:
                                    isMe ? StorkTheme.brandGradient : null,
                                color: isMe ? null : StorkTheme.surface,
                                borderRadius:
                                    BorderRadius.circular(20).copyWith(
                                  bottomRight:
                                      isMe ? const Radius.circular(4) : null,
                                  bottomLeft:
                                      !isMe ? const Radius.circular(4) : null,
                                ),
                                border: isMe
                                    ? null
                                    : Border.all(
                                        color: StorkTheme.borderSubtle),
                                boxShadow:
                                    isMe ? null : StorkTheme.softCardShadow,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (!isMe)
                                    const Padding(
                                      padding: EdgeInsets.only(bottom: 5),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.verified_rounded,
                                            size: 13,
                                            color: StorkTheme.primary,
                                          ),
                                          SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Storkia Support Admin',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w900,
                                                color: StorkTheme.primaryDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (attachmentUrl != null &&
                                      attachmentUrl.isNotEmpty) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.network(
                                        attachmentUrl,
                                        height: 140,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    if (text.isNotEmpty)
                                      const SizedBox(height: 6),
                                  ],
                                  if (text.isNotEmpty)
                                    Text(
                                      text,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        color: isMe
                                            ? Colors.white
                                            : StorkTheme.textMain,
                                        height: 1.38,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (_attachment != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: StorkTheme.surface,
                border: Border(top: BorderSide(color: StorkTheme.borderSubtle)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: StorkTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      size: 16,
                      color: StorkTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _attachment!.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _attachment = null),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: StorkTheme.surface,
              border: Border(top: BorderSide(color: StorkTheme.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _pickAttachment,
                    icon: const Icon(
                      Icons.attach_file_rounded,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message to Storkia Support...',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _isSending ? null : _sendMessage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: _isSending ? null : StorkTheme.brandGradient,
                        color: _isSending ? Colors.grey : null,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 18,
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
