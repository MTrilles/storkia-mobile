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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'chat' ||
        event.event == 'MessageSent' ||
        event.channel.startsWith('private-chat.')) {
      _fetchContactsSilently();
    }
  }

  void _onIncomingChatPayload(dynamic payload) {
    if (mounted) {
      _fetchContactsSilently();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchContactsSilently();
    }
  }

  Future<void> _loadData() async {
    try {
      WebSocketService.init(widget.token, userId: widget.authUserId);
      WebSocketService.listenToChat(widget.authUserId, _onIncomingChatPayload);
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
    WebSocketService.removeListener(_onRealtimeEvent);
    WebSocketService.removeChatListener(_onIncomingChatPayload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text('Messages (${contacts.length})'),
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
                      padding: const EdgeInsets.all(28),
                      children: [
                        const SizedBox(height: 90),
                        _buildEmptyState(),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(14),
                      itemCount: contacts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
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
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: StorkTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 36,
              color: StorkTheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Active Conversations Yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StorkTheme.primaryDark,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap "Chat Now" on any product or official store page to message verified merchants directly.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: StorkTheme.textMuted,
              fontSize: 12.5,
              height: 1.4,
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
    final bool hasUnread = contact.unreadCount > 0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: hasUnread
              ? StorkTheme.primary.withValues(alpha: 0.04)
              : StorkTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hasUnread
                ? StorkTheme.primary.withValues(alpha: 0.35)
                : StorkTheme.borderSubtle,
            width: hasUnread ? 1.5 : 1,
          ),
          boxShadow: StorkTheme.softCardShadow,
        ),
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
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: hasUnread
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                            ),
                            if (isSeller) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: StorkTheme.brandLight
                                      .withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'STORE',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w900,
                                    color: StorkTheme.primaryDark,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        timeAgo,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              hasUnread ? FontWeight.w800 : FontWeight.w600,
                          color: hasUnread
                              ? StorkTheme.primary
                              : StorkTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
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
                            color: hasUnread
                                ? StorkTheme.textMain
                                : StorkTheme.textMuted,
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: StorkTheme.brandGradient,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            contact.unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
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
