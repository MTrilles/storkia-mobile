typedef JsonMap = Map<String, dynamic>;

class ChatContact {
  final int id;
  final String firstName;
  final String lastName;
  final String role;
  final String? businessName;
  final String? logoPath;
  final int unreadCount;
  final String? latestMessage;
  final String? latestMessageAt;

  ChatContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.businessName,
    this.logoPath,
    this.unreadCount = 0,
    this.latestMessage,
    this.latestMessageAt,
  });

  String get displayName {
    if (businessName != null && businessName!.trim().isNotEmpty) {
      return businessName!.trim();
    }
    final full = '$firstName $lastName'.trim();
    if (full.isNotEmpty) {
      return full;
    }
    return role == 'Seller' ? 'Official Store' : 'Buyer';
  }

  ChatContact copyWith({
    String? firstName,
    String? lastName,
    String? role,
    String? businessName,
    String? logoPath,
    int? unreadCount,
    String? latestMessage,
    String? latestMessageAt,
  }) {
    return ChatContact(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      role: role ?? this.role,
      businessName: businessName ?? this.businessName,
      logoPath: logoPath ?? this.logoPath,
      unreadCount: unreadCount ?? this.unreadCount,
      latestMessage: latestMessage ?? this.latestMessage,
      latestMessageAt: latestMessageAt ?? this.latestMessageAt,
    );
  }

  factory ChatContact.fromJson(JsonMap json) {
    final JsonMap? sellerProfile = json['seller_profile'] is Map
        ? Map<String, dynamic>.from(json['seller_profile'] as Map)
        : (json['sellerProfile'] is Map
            ? Map<String, dynamic>.from(json['sellerProfile'] as Map)
            : null);

    final JsonMap? logisticsProfile = json['logistics_profile'] is Map
        ? Map<String, dynamic>.from(json['logistics_profile'] as Map)
        : null;

    final JsonMap? buyerProfile = json['buyer_profile'] is Map
        ? Map<String, dynamic>.from(json['buyer_profile'] as Map)
        : null;

    final JsonMap? nestedUser = json['user'] is Map
        ? Map<String, dynamic>.from(json['user'] as Map)
        : null;

    final String resolvedRole = (json['role'] ??
            nestedUser?['role'] ??
            (sellerProfile != null ? 'Seller' : 'Buyer'))
        .toString();

    String first = (json['first_name'] ?? nestedUser?['first_name'] ?? '')
        .toString()
        .trim();
    String last =
        (json['last_name'] ?? nestedUser?['last_name'] ?? '').toString().trim();

    final String fallbackFullName = (json['display_name'] ??
            json['full_name'] ??
            json['name'] ??
            nestedUser?['full_name'] ??
            nestedUser?['name'] ??
            buyerProfile?['username'] ??
            json['username'] ??
            '')
        .toString()
        .trim();

    if (first.isEmpty && last.isEmpty && fallbackFullName.isNotEmpty) {
      final parts = fallbackFullName.split(RegExp(r'\s+'));
      first = parts.first;
      if (parts.length > 1) {
        last = parts.sublist(1).join(' ');
      }
    }

    String? resolvedBusinessName = (json['business_name'] ??
            json['store_name'] ??
            sellerProfile?['business_name'] ??
            logisticsProfile?['business_name'])
        ?.toString()
        .trim();

    if ((resolvedBusinessName == null || resolvedBusinessName.isEmpty) &&
        resolvedRole.toLowerCase() == 'seller' &&
        fallbackFullName.isNotEmpty) {
      resolvedBusinessName = fallbackFullName;
    }

    final String? resolvedLogo = (json['logo_path'] ??
            json['avatar_url'] ??
            json['avatar_path'] ??
            json['photo_url'] ??
            json['avatar'] ??
            sellerProfile?['logo_path'] ??
            sellerProfile?['photo_url'] ??
            logisticsProfile?['logo_path'] ??
            buyerProfile?['avatar_url'] ??
            buyerProfile?['avatar_path'])
        ?.toString()
        .trim();

    String? latestMsgText;
    String? latestMsgTime = (json['latest_message_at'] ??
            json['last_message_at'] ??
            json['updated_at'] ??
            json['created_at'])
        ?.toString();

    final dynamic rawLatest = json['latest_message'] ?? json['last_message'];
    if (rawLatest is Map) {
      latestMsgText = (rawLatest['message'] ??
              rawLatest['body'] ??
              rawLatest['content'] ??
              '')
          .toString();
      latestMsgTime ??= rawLatest['created_at']?.toString();
    } else if (rawLatest != null) {
      latestMsgText = rawLatest.toString();
    }

    return ChatContact(
      id: int.tryParse(
              (json['id'] ?? json['user_id'] ?? json['contact_id'] ?? '0')
                  .toString()) ??
          0,
      firstName: first,
      lastName: last,
      role: resolvedRole,
      businessName:
          (resolvedBusinessName != null && resolvedBusinessName.isNotEmpty)
              ? resolvedBusinessName
              : null,
      logoPath: (resolvedLogo != null && resolvedLogo.isNotEmpty)
          ? resolvedLogo
          : null,
      unreadCount: int.tryParse((json['unread_count'] ??
                  json['unread'] ??
                  json['unread_messages_count'] ??
                  '0')
              .toString()) ??
          0,
      latestMessage: latestMsgText,
      latestMessageAt: latestMsgTime,
    );
  }
}

class ChatMessage {
  final int id;
  final int userId;
  final int receiverId;
  final String role;
  final String message;
  final bool isRead;
  final String time;
  final String? attachmentPath;
  final JsonMap? product;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.receiverId,
    required this.role,
    required this.message,
    required this.isRead,
    required this.time,
    this.attachmentPath,
    this.product,
  });

  static String _formatMessageTime(String? rawTime, String? rawCreatedAt) {
    if (rawTime != null &&
        rawTime.trim().isNotEmpty &&
        !rawTime.contains('T')) {
      return rawTime.trim();
    }
    final source = rawCreatedAt ?? rawTime;
    if (source == null || source.isEmpty) return '';
    final parsed = DateTime.tryParse(source)?.toLocal();
    if (parsed == null) return source;
    final hour12 = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final minute = parsed.minute.toString().padLeft(2, '0');
    final period = parsed.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  factory ChatMessage.fromJson(JsonMap json) {
    final String? attach =
        (json['attachment_url'] ?? json['attachment_path'])?.toString().trim();

    return ChatMessage(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      userId: int.tryParse((json['user_id'] ??
                  json['sender_id'] ??
                  json['sender_user_id'] ??
                  '0')
              .toString()) ??
          0,
      receiverId: int.tryParse(json['receiver_id']?.toString() ?? '0') ?? 0,
      role: json['role']?.toString() ?? 'Buyer',
      message:
          (json['message'] ?? json['body'] ?? json['content'] ?? '').toString(),
      isRead: json['is_read'] == true ||
          json['is_read'] == 1 ||
          json['read_at'] != null,
      time: _formatMessageTime(
        json['time']?.toString() ?? json['created_at_human']?.toString(),
        json['created_at']?.toString(),
      ),
      attachmentPath: (attach != null && attach.isNotEmpty) ? attach : null,
      product: json['product'] is Map
          ? Map<String, dynamic>.from(json['product'] as Map)
          : null,
    );
  }
}
