import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

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

      // Clear local storage to force the UI to log out
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      return response.statusCode == 200;
    } catch (e) {
      // Clear local storage even if there's a network error
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
}
