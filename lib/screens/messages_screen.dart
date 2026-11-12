import 'dart:async';
import 'package:flutter/material.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/chat_models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'chat_screen.dart';

class MessagesScreen extends StatefulWidget {
  final int authUserId;
  final String token;
  final int? initialContactId;

  const MessagesScreen({
    super.key,
    required this.authUserId,
    required this.token,
    this.initialContactId,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  List<ChatContact> contacts = [];
  bool isLoading = true;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();

    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _fetchContactsSilently();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchContactsSilently();
    }
  }

  Future<void> _loadData() async {
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
    final res = await ApiService.fetchContacts(
      widget.token,
      contactId: widget.initialContactId,
    );
    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
    if (res['success'] == true) {
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
    final res = await ApiService.fetchContacts(
      widget.token,
      contactId: widget.initialContactId,
    );
    if (res['success'] == true && mounted) {
      setState(() {
        contacts = List<ChatContact>.from(res['data'] ?? []);
        _sortContacts();
      });
    }
  }

  String _formatTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    final date = DateTime.tryParse(dateString)?.toLocal();
    if (date == null) return dateString;

    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    const months = [
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
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    WebSocketService.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('Messages'),
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : RefreshIndicator(
              color: StorkTheme.primary,
              onRefresh: _fetchContacts,
              child: contacts.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        _buildEmptyState(),
                      ],
                    )
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
          const Text(
            'No active conversations',
            style: TextStyle(
              color: StorkTheme.textMuted,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
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
    final bool isSeller = contact.role.toLowerCase() == 'seller' ||
        (contact.businessName != null && contact.businessName!.isNotEmpty);
    final String displayName = contact.displayName;
    final String logoUrl =
        (contact.logoPath != null && contact.logoPath!.trim().isNotEmpty)
            ? ApiConfig.storageUrl(contact.logoPath, ApiConfig.domainUrl)
            : '';
    final String subtitleText = (contact.latestMessage != null &&
            contact.latestMessage!.trim().isNotEmpty)
        ? contact.latestMessage!.trim()
        : (isSeller ? 'Official Store' : 'Buyer');

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        color: StorkTheme.surface,
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
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
                            fontSize: 20,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: StorkTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
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
                                ? FontWeight.w900
                                : FontWeight.w700,
                            color: StorkTheme.textMain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: contact.unreadCount > 0
                              ? FontWeight.w800
                              : FontWeight.w500,
                          color: contact.unreadCount > 0
                              ? StorkTheme.primary
                              : StorkTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          subtitleText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: contact.unreadCount > 0
                                ? StorkTheme.textMain
                                : StorkTheme.textMuted,
                            fontWeight: contact.unreadCount > 0
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (contact.unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: StorkTheme.primary,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            contact.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
