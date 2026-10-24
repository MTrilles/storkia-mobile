class ChatContact {
  final int id;
  final String firstName;
  final String lastName;
  final String role;
  final String? latestMessageAt;
  final int unreadCount;
  final String? businessName;
  final String? logoPath;

  ChatContact({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.role,
    this.latestMessageAt,
    required this.unreadCount,
    this.businessName,
    this.logoPath,
  });

  factory ChatContact.fromJson(Map<String, dynamic> json) {
    try {
      return ChatContact(
        id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
        firstName: json['first_name']?.toString() ?? 'User',
        lastName: json['last_name']?.toString() ?? '',
        role: json['role']?.toString() ?? 'Buyer',
        latestMessageAt: json['latest_message_at']?.toString(),
        unreadCount: int.tryParse(json['unread_count']?.toString() ?? '0') ?? 0,
        businessName: json['business_name']?.toString(),
        logoPath: json['logo_path']?.toString(),
      );
    } catch (e) {
      return ChatContact(
          id: 0,
          firstName: 'Error',
          lastName: '',
          role: 'Buyer',
          unreadCount: 0);
    }
  }
}

class ChatMessage {
  final int id;
  final int userId;
  final int receiverId;
  final String role;
  final String message;
  final bool isRead;
  final String createdAt;
  final String time;

  ChatMessage({
    required this.id,
    required this.userId,
    required this.receiverId,
    required this.role,
    required this.message,
    required this.isRead,
    required this.createdAt,
    required this.time,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    try {
      String timeStr = json['time']?.toString() ?? '';
      if (timeStr.isEmpty && json['created_at'] != null) {
        try {
          final date = DateTime.parse(json['created_at'].toString()).toLocal();
          final hour = date.hour > 12
              ? date.hour - 12
              : (date.hour == 0 ? 12 : date.hour);
          final ampm = date.hour >= 12 ? 'PM' : 'AM';
          final min = date.minute.toString().padLeft(2, '0');
          timeStr = '$hour:$min $ampm';
        } catch (_) {}
      }

      return ChatMessage(
        id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
        userId: int.tryParse(json['user_id']?.toString() ?? '0') ?? 0,
        receiverId: int.tryParse(json['receiver_id']?.toString() ?? '0') ?? 0,
        role: json['role']?.toString() ?? 'Buyer',
        message: json['message']?.toString() ?? '',
        isRead: json['is_read'] == 1 ||
            json['is_read'] == true ||
            json['is_read'] == '1',
        createdAt: json['created_at']?.toString() ?? '',
        time: timeStr,
      );
    } catch (e) {
      return ChatMessage(
          id: 0,
          userId: 0,
          receiverId: 0,
          role: 'Buyer',
          message: 'Error formatting',
          isRead: true,
          createdAt: '',
          time: '');
    }
  }
}
