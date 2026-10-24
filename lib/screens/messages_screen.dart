import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  final int authUserId;
  final String token;
  final int? initialContactId;

  const MessagesScreen({
    Key? key,
    required this.authUserId,
    required this.token,
    this.initialContactId,
  }) : super(key: key);

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<ChatContact> contacts = [];
  bool isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    _loadData();

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchContactsSilently();
    });
  }

  Future<void> _loadData() async {
    // Wrap WebSocket init in a try-catch so that if the websocket fails to connect
    // when detached, it doesn't prevent _fetchContacts() from executing and retrieving data.
    try {
      WebSocketService.init(widget.token);
      WebSocketService.listenToChat(widget.authUserId, (event) {
        _fetchContactsSilently();
      });
    } catch (_) {}

    await _fetchContacts();
  }

  void _sortContacts() {
    contacts.sort((a, b) {
      final dateA = a.latestMessageAt != null && a.latestMessageAt!.isNotEmpty
          ? DateTime.tryParse(a.latestMessageAt!) ??
              DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0);
      final dateB = b.latestMessageAt != null && b.latestMessageAt!.isNotEmpty
          ? DateTime.tryParse(b.latestMessageAt!) ??
              DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0);
      return dateB.compareTo(dateA);
    });
  }

  Future<void> _fetchContacts() async {
    final res = await ApiService.fetchContacts(widget.token,
        contactId: widget.initialContactId);

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }

    if (res['success']) {
      setState(() {
        contacts = List<ChatContact>.from(res['data'] ?? []);
        _sortContacts();
      });
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message'] ?? 'Failed to load contacts')),
        );
      }
    }
  }

  Future<void> _fetchContactsSilently() async {
    final res = await ApiService.fetchContacts(widget.token,
        contactId: widget.initialContactId);
    if (res['success']) {
      if (mounted) {
        setState(() {
          contacts = List<ChatContact>.from(res['data'] ?? []);
          _sortContacts();
        });
      }
    }
  }

  String _formatTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    final date = DateTime.tryParse(dateString)?.toLocal();
    if (date == null) return '';

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    WebSocketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          'Messages',
          style: TextStyle(
              color: Colors.black, fontSize: 22, fontWeight: FontWeight.w800),
        ),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173)))
          : contacts.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final contact = contacts[index];

                    if (contact.id == 0) return const SizedBox.shrink();

                    return _ContactTile(
                      contact: contact,
                      timeAgo: _formatTime(contact.latestMessageAt),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              contact: contact,
                              token: widget.token,
                              authUserId: widget.authUserId,
                            ),
                          ),
                        );
                        _fetchContactsSilently();
                      },
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text('No active conversations',
              style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  final ChatContact contact;
  final String timeAgo;
  final VoidCallback onTap;

  const _ContactTile({
    required this.contact,
    required this.timeAgo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    bool isSeller = contact.role == 'Seller';

    String displayName = (isSeller &&
            contact.businessName != null &&
            contact.businessName!.isNotEmpty)
        ? contact.businessName!
        : '${contact.firstName} ${contact.lastName}'.trim();

    if (displayName.isEmpty) displayName = 'User';
    bool hasLogo =
        isSeller && contact.logoPath != null && contact.logoPath!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        color: Colors.white,
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: const Color(0xFFCF4173).withOpacity(0.2),
                  backgroundImage: hasLogo
                      ? NetworkImage(
                          'https://dev.storkia.shop/storage/${contact.logoPath}')
                      : null,
                  child: !hasLogo
                      ? Text(
                          displayName.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              color: Color(0xFFCF4173),
                              fontWeight: FontWeight.bold,
                              fontSize: 20),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: contact.unreadCount > 0
                                ? FontWeight.w800
                                : FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: contact.unreadCount > 0
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: contact.unreadCount > 0
                              ? const Color(0xFFCF4173)
                              : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSeller ? 'Official Store' : 'Buyer',
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                            fontWeight: FontWeight.w500),
                      ),
                      if (contact.unreadCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            contact.unreadCount.toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
