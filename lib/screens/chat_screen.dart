import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

class ChatScreen extends StatefulWidget {
  final ChatContact contact;
  final String token;
  final int authUserId;

  const ChatScreen({
    Key? key,
    required this.contact,
    required this.token,
    required this.authUserId,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ChatMessage> messages = [];
  bool isSending = false;
  bool isFetching = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    WebSocketService.listenToChat(widget.authUserId, _handleRealTimeMessage);

    // Silent background polling to ensure instant sync if WebSockets fail
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchMessagesSilently();
    });
  }

  void _handleRealTimeMessage(dynamic event) {
    if (event['message'] != null) {
      final msg = ChatMessage.fromJson(event['message']);
      if (msg.userId == widget.contact.id) {
        if (mounted) {
          setState(() {
            messages.add(msg);
          });
          _scrollToBottom();
          ApiService.markAsRead(widget.token, widget.contact.id);
        }
      }
    }
  }

  Future<void> _fetchMessages() async {
    final res = await ApiService.fetchMessages(widget.token, widget.contact.id);

    if (mounted) {
      setState(() {
        isFetching = false;
      });
    }

    if (res['success']) {
      setState(() {
        messages = res['data'];
      });
      _scrollToBottom();
      ApiService.markAsRead(widget.token, widget.contact.id);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to load messages')),
        );
      }
    }
  }

  Future<void> _fetchMessagesSilently() async {
    final res = await ApiService.fetchMessages(widget.token, widget.contact.id);
    if (res['success']) {
      final List<ChatMessage> newMessages = res['data'];
      if (newMessages.length != messages.length) {
        if (mounted) {
          setState(() {
            messages = newMessages;
          });
          _scrollToBottom();
          ApiService.markAsRead(widget.token, widget.contact.id);
        }
      }
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || isSending) return;

    setState(() => isSending = true);
    final backup = text;
    _msgController.clear();

    final res =
        await ApiService.sendMessage(widget.token, widget.contact.id, text);

    if (res['success']) {
      if (mounted) {
        setState(() {
          messages.add(res['data']);
        });
        _scrollToBottom();
      }
    } else {
      _msgController.text = backup;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['message'] ?? 'Failed to send message')));
      }
    }

    if (mounted) {
      setState(() => isSending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String displayName = (widget.contact.businessName != null &&
            widget.contact.businessName!.isNotEmpty)
        ? widget.contact.businessName!
        : '${widget.contact.firstName} ${widget.contact.lastName}'.trim();
    if (displayName.isEmpty) displayName = 'User';

    bool hasLogo =
        widget.contact.logoPath != null && widget.contact.logoPath!.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFCF4173).withOpacity(0.2),
              backgroundImage: hasLogo
                  ? NetworkImage(
                      'https://dev.storkia.shop/storage/${widget.contact.logoPath}')
                  : null,
              child: !hasLogo
                  ? Text(
                      displayName.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          color: Color(0xFFCF4173),
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    )
                  : null,
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
                        color: Colors.black,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Colors.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 4),
                      const Text('Active now',
                          style: TextStyle(color: Colors.green, fontSize: 11)),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: isFetching
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFFCF4173)))
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey[200]!)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.grey[500]),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          isSending ? Colors.grey : const Color(0xFFCF4173),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool isMe;

  const _ChatBubble({required this.msg, required this.isMe});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFCF4173) : Colors.white,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomRight: isMe ? const Radius.circular(4) : null,
                  bottomLeft: !isMe ? const Radius.circular(4) : null,
                ),
                border: !isMe ? Border.all(color: Colors.grey[200]!) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Text(
                msg.message,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  msg.time,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all, size: 14, color: Colors.grey[400]),
                ]
              ],
            )
          ],
        ),
      ),
    );
  }
}
