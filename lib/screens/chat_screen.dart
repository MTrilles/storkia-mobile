import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

typedef JsonMap = Map<String, dynamic>;

class ChatScreen extends StatefulWidget {
  final ChatContact contact;
  final String token;
  final int authUserId;

  const ChatScreen({
    super.key,
    required this.contact,
    required this.token,
    required this.authUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late ChatContact _contact;
  List<ChatMessage> messages = [];
  bool isSending = false;
  bool isFetching = true;
  XFile? _attachment;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _contact = widget.contact;
    _fetchMessages();
    WebSocketService.init(widget.token, userId: widget.authUserId);
    WebSocketService.listenToChat(widget.authUserId, _handleRealTimeMessage);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchMessagesSilently();
    }
  }

  void _handleRealTimeMessage(dynamic event) {
    if (!mounted) return;
    if (event is Map) {
      final rawMsg = event['payload'] ?? event['message'] ?? event;
      if (rawMsg is Map) {
        final msg = ChatMessage.fromJson(JsonMap.from(rawMsg));
        if (msg.userId == _contact.id) {
          final exists = messages.any((m) => m.id == msg.id);
          if (!exists) {
            HapticFeedback.lightImpact();
            setState(() {
              messages.add(msg);
            });
            _scrollToBottom();
            ApiService.markAsRead(widget.token, _contact.id);
          }
          return;
        }
      }
    }
    _fetchMessagesSilently();
  }

  Future<void> _fetchMessages() async {
    final res = await ApiService.fetchMessages(widget.token, _contact.id);
    if (!mounted) return;
    setState(() {
      isFetching = false;
      if (res['contact'] is ChatContact) {
        final fetchedContact = res['contact'] as ChatContact;
        _contact = _contact.copyWith(
          businessName: fetchedContact.businessName ?? _contact.businessName,
          firstName: fetchedContact.firstName.isNotEmpty
              ? fetchedContact.firstName
              : _contact.firstName,
          lastName: fetchedContact.lastName.isNotEmpty
              ? fetchedContact.lastName
              : _contact.lastName,
          logoPath: fetchedContact.logoPath ?? _contact.logoPath,
        );
      }
    });

    if (res['success'] == true) {
      setState(() {
        messages = List<ChatMessage>.from(res['data'] ?? []);
      });
      _scrollToBottom();
      ApiService.markAsRead(widget.token, _contact.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to load messages')),
      );
    }
  }

  Future<void> _fetchMessagesSilently() async {
    final res = await ApiService.fetchMessages(widget.token, _contact.id);
    if (!mounted || res['success'] != true) return;
    if (res['contact'] is ChatContact) {
      final fetchedContact = res['contact'] as ChatContact;
      if ((_contact.businessName == null || _contact.businessName!.isEmpty) &&
          fetchedContact.businessName != null) {
        setState(() {
          _contact = _contact.copyWith(
            businessName: fetchedContact.businessName,
            logoPath: fetchedContact.logoPath ?? _contact.logoPath,
          );
        });
      }
    }
    final List<ChatMessage> newMessages =
        List<ChatMessage>.from(res['data'] ?? []);
    if (newMessages.length != messages.length) {
      setState(() {
        messages = newMessages;
      });
      _scrollToBottom();
      ApiService.markAsRead(widget.token, _contact.id);
    }
  }

  Future<void> _pickAttachment() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      HapticFeedback.selectionClick();
      setState(() => _attachment = picked);
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if ((text.isEmpty && _attachment == null) || isSending) return;

    HapticFeedback.lightImpact();
    setState(() => isSending = true);
    final backup = text;
    final fileToSend = _attachment;

    _msgController.clear();
    setState(() => _attachment = null);

    final res = await ApiService.sendMessage(
      widget.token,
      _contact.id,
      text,
      attachmentPath: fileToSend?.path,
    );

    if (!mounted) return;
    if (res['success'] == true && res['data'] is ChatMessage) {
      setState(() {
        messages.add(res['data'] as ChatMessage);
        isSending = false;
      });
      _scrollToBottom();
    } else {
      _msgController.text = backup;
      setState(() {
        _attachment = fileToSend;
        isSending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to send message')),
      );
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebSocketService.removeChatListener(_handleRealTimeMessage);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String displayName = _contact.displayName;
    final String logoUrl =
        (_contact.logoPath != null && _contact.logoPath!.trim().isNotEmpty)
            ? ApiConfig.storageUrl(_contact.logoPath, ApiConfig.domainUrl)
            : '';

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: StorkTheme.primary.withValues(alpha: 0.25),
                  width: 1.5,
                ),
              ),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: StorkTheme.primary.withValues(alpha: 0.14),
                backgroundImage:
                    logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                child: logoUrl.isEmpty
                    ? Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          color: StorkTheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: StorkTheme.primaryDark,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
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
                      const Flexible(
                        child: Text(
                          'Official Store \u2022 Active now',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: StorkTheme.success,
                            fontSize: 11,
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
            child: isFetching
                ? const Center(
                    child: CircularProgressIndicator(color: StorkTheme.primary),
                  )
                : messages.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(28),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color:
                                      StorkTheme.primary.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  color: StorkTheme.primary,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Chat with $displayName',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Ask about product specifications, stock availability, or custom bundle requests.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: StorkTheme.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final msg = messages[index];
                          final isMe = msg.userId == widget.authUserId;
                          return _ChatBubble(msg: msg, isMe: isMe);
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: const BoxDecoration(
              color: StorkTheme.surface,
              border: Border(top: BorderSide(color: StorkTheme.borderSubtle)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _pickAttachment,
                    icon: const Icon(
                      Icons.photo_library_outlined,
                      color: StorkTheme.primaryDark,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      maxLines: 4,
                      minLines: 1,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: isSending ? null : StorkTheme.brandGradient,
                        color: isSending ? Colors.grey : null,
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

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;

  const _ChatBubble({required this.msg, required this.isMe});

  void _openFullScreenImage(BuildContext context, String imageUrl) {
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black.withValues(alpha: 0.92),
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.6,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 48,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(dialogContext).padding.top + 12,
                right: 16,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _copyMessageText(BuildContext context) async {
    final text = msg.message.trim();
    if (text.isEmpty) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String attachmentUrl =
        (msg.attachmentPath != null && msg.attachmentPath!.isNotEmpty)
            ? ApiConfig.storageUrl(msg.attachmentPath, ApiConfig.domainUrl)
            : '';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onLongPress: () => _copyMessageText(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                decoration: BoxDecoration(
                  gradient: isMe ? StorkTheme.brandGradient : null,
                  color: isMe ? null : StorkTheme.surface,
                  borderRadius: BorderRadius.circular(20).copyWith(
                    bottomRight: isMe ? const Radius.circular(4) : null,
                    bottomLeft: !isMe ? const Radius.circular(4) : null,
                  ),
                  border:
                      !isMe ? Border.all(color: StorkTheme.borderSubtle) : null,
                  boxShadow: !isMe ? StorkTheme.softCardShadow : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (msg.product != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.black.withValues(alpha: 0.16)
                              : StorkTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 14,
                              color:
                                  isMe ? Colors.white : StorkTheme.primaryDark,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Product Inquiry: ${msg.product!['name'] ?? ''}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: isMe
                                      ? Colors.white
                                      : StorkTheme.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (attachmentUrl.isNotEmpty) ...[
                      GestureDetector(
                        onTap: () =>
                            _openFullScreenImage(context, attachmentUrl),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            attachmentUrl,
                            height: 155,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Padding(
                              padding: EdgeInsets.all(16),
                              child: Icon(
                                Icons.broken_image_outlined,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (msg.message.isNotEmpty) const SizedBox(height: 6),
                    ],
                    if (msg.message.isNotEmpty)
                      Text(
                        msg.message,
                        style: TextStyle(
                          color: isMe ? Colors.white : StorkTheme.textMain,
                          fontSize: 14,
                          height: 1.38,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.time,
                  style: const TextStyle(
                    color: StorkTheme.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all_rounded,
                    size: 14,
                    color:
                        msg.isRead ? StorkTheme.primary : StorkTheme.textMuted,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
