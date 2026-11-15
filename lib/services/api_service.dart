import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/cart_model.dart';
import '../models/chat_models.dart';

typedef JsonMap = Map<String, dynamic>;
typedef SellerCacheMap = Map<int, JsonMap>;

class ApiService {
  static final http.Client httpClient = http.Client();
  static String? socketId;

  static SellerCacheMap _sellerByUserIdCache = {};
  static SellerCacheMap _sellerByProfileIdCache = {};
  static DateTime? _sellerCacheLoadedAt;

  static Map<String, String> buildHeaders(
    String? token, {
    bool isJson = false,
  }) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'Connection': 'keep-alive',
      if (isJson) 'Content-Type': 'application/json',
    };
    if (token != null && token.trim().isNotEmpty) {
      headers['Authorization'] = 'Bearer ${token.trim()}';
    }
    if (socketId != null && socketId!.isNotEmpty) {
      headers['X-Socket-ID'] = socketId!;
    }
    return headers;
  }

  static String _extractError(dynamic data, String fallback) {
    if (data is Map) {
      if (data['errors'] is Map) {
        final errors = data['errors'] as Map;
        if (errors.isNotEmpty) {
          final firstVal = errors.values.first;
          if (firstVal is List && firstVal.isNotEmpty) {
            return firstVal.first.toString();
          }
          return firstVal.toString();
        }
      }
      if (data['message'] != null && data['message'].toString().isNotEmpty) {
        return data['message'].toString();
      }
    }
    return fallback;
  }

  static Future<JsonMap> sendOtp(String email) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/send-otp'),
            headers: buildHeaders(null, isJson: true),
            body: jsonEncode({'email': email}),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': data,
          'cooldown': data['cooldown'] ?? 60,
        };
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to send verification code.'),
          'cooldown': data['cooldown'] ?? 0,
        };
      }
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to connect to server. Please check your internet.',
      };
    }
  }

  static Future<JsonMap> verifyOtp(String email, String code) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/verify-otp'),
            headers: buildHeaders(null, isJson: true),
            body: jsonEncode({'email': email, 'code': code}),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': data,
          'verification_token': data['verification_token'],
        };
      } else {
        return {
          'success': false,
          'message':
              _extractError(data, 'Invalid or expired verification code.'),
        };
      }
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to connect to server. Please check your internet.',
      };
    }
  }

  static Future<JsonMap> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/login'),
            headers: buildHeaders(null, isJson: true),
            body: jsonEncode({
              'email': email,
              'password': password,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final role = data['user']?['role']?.toString() ?? 'Buyer';
        if (role.toLowerCase() != 'buyer') {
          return {
            'success': false,
            'message':
                'You have a $role account. Please sign in through the web $role Portal.',
          };
        }
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(
              data, 'Login failed. Please check your credentials.'),
        };
      }
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to connect to server. Please check your internet.',
      };
    }
  }

  static Future<bool> logout(String token) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/logout'),
            headers: buildHeaders(token, isJson: true),
          )
          .timeout(const Duration(seconds: 8));
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('storkia_auth_token');
      await prefs.remove('storkia_auth_user');
      return response.statusCode == 200;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('storkia_auth_token');
      await prefs.remove('storkia_auth_user');
      return false;
    }
  }

  static Future<JsonMap> register({
    required String firstName,
    required String lastName,
    String? middleInitial,
    required String sex,
    required String birthday,
    required String email,
    String? verificationToken,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/register'),
            headers: buildHeaders(null, isJson: true),
            body: jsonEncode({
              'first_name': firstName,
              'last_name': lastName,
              'middle_initial': middleInitial,
              'sex': sex,
              'birthday': birthday,
              'email': email,
              'verification_token': verificationToken,
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Registration failed.'),
        };
      }
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to connect to server. Please check your internet.',
      };
    }
  }

  static Future<JsonMap> getSanctionStatus(String token) async {
    try {
      final response = await httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/account/sanction'),
            headers: buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data['data']};
      }
      return {
        'success': false,
        'message': _extractError(data, 'Failed to load account status.'),
      };
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> submitSanctionAppeal({
    required String token,
    required String explanation,
    String? photoPath,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/account/sanction/appeal'),
      );
      request.headers.addAll(buildHeaders(token));
      request.fields['appeal_explanation'] = explanation;
      if (photoPath != null && photoPath.isNotEmpty) {
        request.files.add(
          await http.MultipartFile.fromPath('supporting_photo', photoPath),
        );
      }
      final streamed =
          await httpClient.send(request).timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'data': data};
      }
      return {
        'success': false,
        'message': _extractError(data, 'Failed to submit appeal.'),
      };
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> getProducts(
    String token, {
    int page = 1,
    int perPage = 10,
    String? category,
    String? subcategory,
    int? sellerId,
  }) async {
    try {
      String url = '${ApiConfig.baseUrl}/products?page=$page&per_page=$perPage';
      if (category != null && category.isNotEmpty) {
        url += '&category=${Uri.encodeComponent(category)}';
      }
      if (subcategory != null && subcategory.isNotEmpty) {
        url += '&subcategory=${Uri.encodeComponent(subcategory)}';
      }
      if (sellerId != null) {
        url += '&seller_id=$sellerId';
      }

      final response = await httpClient
          .get(
            Uri.parse(url),
            headers: buildHeaders(token, isJson: true),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to fetch products.'),
        };
      }
    } catch (_) {
      return {
        'success': false,
        'message': 'Unable to load products. Please check your connection.',
      };
    }
  }

  static Future<JsonMap> getCartItems(String token) async {
    try {
      final response = await httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/cart'),
            headers: buildHeaders(token, isJson: true),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        final List<dynamic> items =
            data['data'] is List ? data['data'] as List<dynamic> : <dynamic>[];
        final List<CartItem> cartItems = [
          for (final e in items)
            if (e is Map) CartItem.fromJson(JsonMap.from(e)),
        ];
        return {'success': true, 'data': cartItems};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to load cart'),
        };
      }
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> addToCart({
    required String token,
    required int productId,
    required int quantity,
    String? variant,
    String? subVariant,
  }) async {
    try {
      final response = await httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/cart'),
            headers: buildHeaders(token, isJson: true),
            body: jsonEncode({
              'product_id': productId,
              'quantity': quantity,
              'variant': variant,
              'sub_variant': subVariant,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 || response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to add item to cart.'),
        };
      }
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> updateCartQuantity(
      String token, int cartId, int quantity) async {
    try {
      final response = await httpClient
          .put(
            Uri.parse('${ApiConfig.baseUrl}/cart/$cartId'),
            headers: buildHeaders(token, isJson: true),
            body: jsonEncode({'quantity': quantity}),
          )
          .timeout(ApiConfig.requestTimeout);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to update quantity.'),
        };
      }
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> removeCartItem(String token, int cartId) async {
    try {
      final response = await httpClient
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/cart/$cartId'),
            headers: buildHeaders(token, isJson: true),
          )
          .timeout(ApiConfig.requestTimeout);
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        return {'success': true, 'data': data};
      } else {
        return {
          'success': false,
          'message': _extractError(data, 'Failed to remove item.'),
        };
      }
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<void> _ensureSellerDirectoryCache(String token) async {
    final now = DateTime.now();
    if (_sellerByUserIdCache.isNotEmpty &&
        _sellerCacheLoadedAt != null &&
        now.difference(_sellerCacheLoadedAt!).inMinutes < 10) {
      return;
    }

    try {
      final response = await httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/sellers'),
            headers: buildHeaders(token),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        List<dynamic> rawSellers = [];
        if (body is Map) {
          final d = body['data'];
          if (d is List) {
            rawSellers = d;
          } else if (d is Map) {
            if (d['sellers'] is List) {
              rawSellers = d['sellers'] as List<dynamic>;
            } else if (d['data'] is List) {
              rawSellers = d['data'] as List<dynamic>;
            }
          }
        }
        final SellerCacheMap byUser = {};
        final SellerCacheMap byProfile = {};
        for (final item in rawSellers) {
          if (item is Map) {
            final map = JsonMap.from(item);
            final int uid =
                int.tryParse(map['user_id']?.toString() ?? '0') ?? 0;
            final int pid = int.tryParse(map['id']?.toString() ?? '0') ?? 0;
            if (uid > 0) byUser[uid] = map;
            if (pid > 0) byProfile[pid] = map;
          }
        }
        if (byUser.isNotEmpty) {
          _sellerByUserIdCache = byUser;
          _sellerByProfileIdCache = byProfile;
          _sellerCacheLoadedAt = now;
        }
      }
    } catch (_) {}
  }

  static Future<JsonMap> fetchContacts(String token, {int? contactId}) async {
    try {
      String url = '${ApiConfig.baseUrl}/messages/contacts';
      if (contactId != null) {
        url += '?contact=$contactId';
      }

      final response = await httpClient
          .get(
            Uri.parse(url),
            headers: buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawList = [];

        if (data is Map && data['success'] == true && data['data'] != null) {
          final d = data['data'];
          if (d is List) {
            rawList = d;
          } else if (d is Map) {
            if (d['contacts'] is List) {
              rawList = d['contacts'] as List<dynamic>;
            } else {
              rawList = d.values.toList();
            }
          }
        } else if (data is Map && data['contacts'] is List) {
          rawList = data['contacts'] as List<dynamic>;
        } else if (data is List) {
          rawList = data;
        }

        List<ChatContact> contacts = [
          for (final e in rawList)
            if (e is Map) ChatContact.fromJson(JsonMap.from(e)),
        ];

        final bool needsSellerLookup = contacts.any((c) =>
                (c.businessName == null || c.businessName!.isEmpty) &&
                c.firstName.isEmpty) ||
            (contactId != null && !contacts.any((c) => c.id == contactId));

        if (needsSellerLookup || _sellerByUserIdCache.isEmpty) {
          await _ensureSellerDirectoryCache(token);
        }

        contacts = [
          for (final c in contacts)
            if (_sellerByUserIdCache.containsKey(c.id) ||
                _sellerByProfileIdCache.containsKey(c.id))
              c.copyWith(
                businessName: (c.businessName != null &&
                        c.businessName!.trim().isNotEmpty)
                    ? c.businessName
                    : (_sellerByUserIdCache[c.id]?['business_name'] ??
                            _sellerByProfileIdCache[c.id]?['business_name'])
                        ?.toString(),
                logoPath: (c.logoPath != null && c.logoPath!.trim().isNotEmpty)
                    ? c.logoPath
                    : (_sellerByUserIdCache[c.id]?['logo_path'] ??
                            _sellerByProfileIdCache[c.id]?['logo_path'])
                        ?.toString(),
              )
            else
              c,
        ];

        if (contactId != null && !contacts.any((c) => c.id == contactId)) {
          final sellerMatch = _sellerByUserIdCache[contactId] ??
              _sellerByProfileIdCache[contactId];
          if (sellerMatch != null) {
            contacts.insert(
              0,
              ChatContact(
                id: int.tryParse(sellerMatch['user_id']?.toString() ?? '') ??
                    contactId,
                firstName: '',
                lastName: '',
                role: 'Seller',
                businessName: sellerMatch['business_name']?.toString(),
                logoPath: sellerMatch['logo_path']?.toString(),
              ),
            );
          }
        }

        return {'success': true, 'data': contacts};
      }
      return {
        'success': false,
        'message': 'Failed to load contacts: ${response.statusCode}',
      };
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> fetchUnreadMessageCount(String token) async {
    try {
      final response = await httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/messages/contacts'),
            headers: buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawList = [];
        if (data is Map && data['data'] is List) {
          rawList = data['data'] as List<dynamic>;
        } else if (data is Map &&
            data['data'] is Map &&
            data['data']['contacts'] is List) {
          rawList = data['data']['contacts'] as List<dynamic>;
        } else if (data is List) {
          rawList = data;
        }
        int totalUnread = 0;
        for (final item in rawList) {
          if (item is Map) {
            totalUnread += int.tryParse(
                    (item['unread_count'] ?? item['unread'] ?? '0')
                        .toString()) ??
                0;
          }
        }
        return {'success': true, 'count': totalUnread};
      }
      return {'success': false, 'count': 0};
    } catch (_) {
      return {'success': false, 'count': 0};
    }
  }

  static Future<JsonMap> fetchMessages(String token, int contactId) async {
    try {
      final response = await httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/messages/fetch/$contactId'),
            headers: buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<dynamic> rawList = [];
        JsonMap? contactInfo;

        if (data is Map && data['success'] == true && data['data'] != null) {
          final d = data['data'];
          if (d is List) {
            rawList = d;
          } else if (d is Map) {
            if (d['messages'] is List) {
              rawList = d['messages'] as List<dynamic>;
            } else {
              rawList = d.values.toList();
            }
            if (d['contact'] is Map) {
              contactInfo = JsonMap.from(d['contact'] as Map);
            }
          }
          if (data['contact'] is Map) {
            contactInfo = JsonMap.from(data['contact'] as Map);
          }
        } else if (data is List) {
          rawList = data;
        }

        final List<ChatMessage> messages = [
          for (final e in rawList)
            if (e is Map) ChatMessage.fromJson(JsonMap.from(e)),
        ];

        return {
          'success': true,
          'data': messages,
          if (contactInfo != null) 'contact': ChatContact.fromJson(contactInfo),
        };
      }
      return {'success': false, 'message': 'Failed to load messages'};
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<JsonMap> sendMessage(
    String token,
    int receiverId,
    String message, {
    String? attachmentPath,
    int? productId,
  }) async {
    try {
      http.Response response;
      if (attachmentPath != null && attachmentPath.isNotEmpty) {
        final req = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiConfig.baseUrl}/messages'),
        );
        req.headers.addAll(buildHeaders(token));
        req.fields['receiver_id'] = '$receiverId';
        req.fields['message'] =
            message.isNotEmpty ? message : 'Sent an attachment';
        if (productId != null) {
          req.fields['product_id'] = '$productId';
        }
        req.files.add(
          await http.MultipartFile.fromPath('attachment', attachmentPath),
        );
        final streamed =
            await httpClient.send(req).timeout(ApiConfig.requestTimeout);
        response = await http.Response.fromStream(streamed);
      } else {
        response = await httpClient
            .post(
              Uri.parse('${ApiConfig.baseUrl}/messages'),
              headers: buildHeaders(token, isJson: true),
              body: jsonEncode({
                'receiver_id': receiverId,
                'message': message,
                if (productId != null) 'product_id': productId,
              }),
            )
            .timeout(ApiConfig.requestTimeout);
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        JsonMap? msgData;
        if (data is Map) {
          if (data['data'] is Map) {
            msgData = JsonMap.from(data['data'] as Map);
          } else {
            msgData = JsonMap.from(data);
          }
        }
        if (msgData != null && !msgData.containsKey('error')) {
          return {'success': true, 'data': ChatMessage.fromJson(msgData)};
        }
      }
      return {
        'success': false,
        'message': _extractError(data, 'Failed to send message'),
      };
    } catch (_) {
      return {'success': false, 'message': 'Network error occurred.'};
    }
  }

  static Future<void> markAsRead(String token, int contactId) async {
    try {
      await httpClient
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/messages/$contactId/read'),
            headers: buildHeaders(token),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
