import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/cart_model.dart';
import '../models/chat_models.dart';

class ApiService {
  static Future<Map<String, dynamic>> sendOtp(String email) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/send-otp'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        String errMsg = data['message'] ?? 'Failed to send verification code.';
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          errMsg = errors.values.first[0].toString();
        }
        return {'success': false, 'message': errMsg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/verify-otp'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'code': code}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Invalid code.'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final role = data['user']?['role'] ?? '';
        if (role.toLowerCase() != 'buyer') {
          return {
            'success': false,
            'message':
                'You have a $role account. Please access your account on a desktop to view the dashboard.'
          };
        }
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message':
              data['message'] ?? 'Login failed. Please check credentials.'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<bool> logout(String token) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/logout'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      return response.statusCode == 200;
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      return false;
    }
  }

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    String? middleInitial,
    required String sex,
    required String birthday,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'first_name': firstName,
          'last_name': lastName,
          'middle_initial': middleInitial,
          'sex': sex,
          'birthday': birthday,
          'email': email,
          'password': password,
          'password_confirmation': passwordConfirmation,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        String errMsg = data['message'] ?? 'Registration failed.';
        if (data['errors'] != null) {
          final errors = data['errors'] as Map<String, dynamic>;
          errMsg = errors.values.first[0].toString();
        }
        return {'success': false, 'message': errMsg};
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getProducts(String token,
      {int page = 1,
      int perPage = 6,
      String? category,
      String? subcategory}) async {
    try {
      String url = '${ApiConfig.baseUrl}/products?page=$page&per_page=$perPage';

      if (category != null && category.isNotEmpty) {
        url += '&category=${Uri.encodeComponent(category)}';
      }
      if (subcategory != null && subcategory.isNotEmpty) {
        url += '&subcategory=${Uri.encodeComponent(subcategory)}';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to fetch products.'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getCartItems(String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/cart'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        List items = data['data'] ?? [];
        List<CartItem> cartItems =
            items.map((e) => CartItem.fromJson(e)).toList();
        return {'success': true, 'data': cartItems};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to load cart'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> addToCart({
    required String token,
    required int productId,
    required int quantity,
    String? variant,
    String? subVariant,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/cart'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'product_id': productId,
          'quantity': quantity,
          'variant': variant,
          'sub_variant': subVariant,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to add item'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> updateCartQuantity(
      String token, int cartId, int quantity) async {
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/cart/$cartId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'quantity': quantity}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to update item'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> removeCartItem(
      String token, int cartId) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/cart/$cartId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to remove item'
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> fetchContacts(String token,
      {int? contactId}) async {
    try {
      String url = '${ApiConfig.baseUrl}/messages/contacts';
      if (contactId != null) {
        url += '?contact=$contactId';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List rawList = [];
        if (data is Map && data['success'] == true && data['data'] != null) {
          rawList = data['data'] is List
              ? data['data']
              : (data['data'] as Map).values.toList();
        } else if (data is List) {
          rawList = data;
        }

        List<ChatContact> contacts = rawList.map((e) {
          return ChatContact.fromJson(Map<String, dynamic>.from(e));
        }).toList();

        return {'success': true, 'data': contacts};
      }
      return {
        'success': false,
        'message': 'Failed to load contacts: ${response.statusCode}'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> fetchUnreadMessageCount(
      String token) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/unread-count'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map) {
          int count = 0;
          if (data['data'] != null &&
              data['data'] is Map &&
              data['data']['count'] != null) {
            count = int.tryParse(data['data']['count'].toString()) ?? 0;
          } else if (data['count'] != null) {
            count = int.tryParse(data['count'].toString()) ?? 0;
          }
          return {'success': true, 'count': count};
        }
      }
      return {'success': false, 'count': 0};
    } catch (e) {
      return {'success': false, 'count': 0};
    }
  }

  static Future<Map<String, dynamic>> fetchMessages(
      String token, int contactId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/messages/fetch/$contactId'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        List rawList = [];
        if (data is Map && data['success'] == true && data['data'] != null) {
          rawList = data['data'] is List
              ? data['data']
              : (data['data'] as Map).values.toList();
        } else if (data is List) {
          rawList = data;
        }

        List<ChatMessage> messages = rawList.map((e) {
          return ChatMessage.fromJson(Map<String, dynamic>.from(e));
        }).toList();

        return {'success': true, 'data': messages};
      }
      return {'success': false, 'message': 'Failed to load messages'};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<Map<String, dynamic>> sendMessage(
      String token, int receiverId, String message) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'receiver_id': receiverId,
          'message': message,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        Map<String, dynamic>? msgData;
        if (data is Map) {
          if (data.containsKey('data') && data['data'] is Map) {
            msgData = Map<String, dynamic>.from(data['data']);
          } else {
            msgData = Map<String, dynamic>.from(data);
          }
        }

        if (msgData != null && !msgData.containsKey('error')) {
          return {'success': true, 'data': ChatMessage.fromJson(msgData)};
        }
      }

      return {
        'success': false,
        'message': (data is Map && data.containsKey('message'))
            ? data['message']
            : 'Failed to send message'
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }

  static Future<void> markAsRead(String token, int contactId) async {
    try {
      await http.patch(
        Uri.parse('${ApiConfig.baseUrl}/messages/$contactId/read'),
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
    } catch (_) {}
  }
}
