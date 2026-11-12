import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';

class AuthState {
  final UserModel? user;
  final String? token;
  final bool isLoading;

  const AuthState({
    this.user,
    this.token,
    this.isLoading = true,
  });

  bool get isAuthenticated =>
      user != null && token != null && token!.isNotEmpty;

  AuthState copyWith({
    UserModel? user,
    String? token,
    bool? isLoading,
    bool clearAuth = false,
  }) {
    if (clearAuth) {
      return const AuthState(user: null, token: null, isLoading: false);
    }
    return AuthState(
      user: user ?? this.user,
      token: token ?? this.token,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    loadStoredAuth();
  }

  Future<bool> restoreSession() async {
    await loadStoredAuth();
    return state.isAuthenticated;
  }

  Future<void> loadStoredAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedToken = prefs.getString('storkia_auth_token');
      final storedUserStr = prefs.getString('storkia_auth_user');

      if (storedToken != null &&
          storedToken.isNotEmpty &&
          storedUserStr != null &&
          storedUserStr.isNotEmpty) {
        final decoded = json.decode(storedUserStr);
        if (decoded is Map) {
          final user = UserModel.fromJson(Map<String, dynamic>.from(decoded));
          state = AuthState(user: user, token: storedToken, isLoading: false);
          await refreshUserProfile();
          return;
        }
      }
    } catch (_) {}
    state = const AuthState(user: null, token: null, isLoading: false);
  }

  Future<void> login(UserModel user, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storkia_auth_token', token);
    await prefs.setString('storkia_auth_user', json.encode(user.toJson()));
    state = AuthState(user: user, token: token, isLoading: false);
    await refreshUserProfile();
  }

  Future<void> updateUser(UserModel updatedUser) async {
    final merged = updatedUser.copyWith(
      username: updatedUser.username ?? state.user?.username,
      avatarPath: updatedUser.avatarPath ?? state.user?.avatarPath,
    );
    state = state.copyWith(user: merged);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storkia_auth_user', json.encode(merged.toJson()));
  }

  Future<void> refreshUserProfile() async {
    final token = state.token;
    if (token == null || token.isEmpty) return;

    try {
      final headers = {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

      final responses = await Future.wait([
        http
            .get(Uri.parse('${ApiConfig.baseUrl}/user'), headers: headers)
            .timeout(ApiConfig.requestTimeout),
        http
            .get(Uri.parse('${ApiConfig.baseUrl}/profile'), headers: headers)
            .timeout(ApiConfig.requestTimeout),
        http
            .get(
              Uri.parse('${ApiConfig.baseUrl}/account/identity-verification'),
              headers: headers,
            )
            .timeout(ApiConfig.requestTimeout),
      ]);

      UserModel? baseUser = state.user;

      final userRes = responses[0];
      if (userRes.statusCode == 200) {
        final body = json.decode(userRes.body);
        final rawUser =
            body is Map ? (body['data'] ?? body['user'] ?? body) : null;
        if (rawUser is Map) {
          baseUser = UserModel.fromJson(Map<String, dynamic>.from(rawUser));
        }
      }

      if (baseUser == null) return;

      String? profileUsername = baseUser.username;
      String? profileAvatar = baseUser.avatarPath;
      bool hasProfileResponse = false;

      final profRes = responses[1];
      if (profRes.statusCode == 200) {
        final body = json.decode(profRes.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          hasProfileResponse = true;
          final pMap = d['profile'] is Map
              ? Map<String, dynamic>.from(d['profile'] as Map)
              : Map<String, dynamic>.from(d);

          final String uName =
              (pMap['username'] ?? d['username'] ?? '').toString().trim();
          if (uName.isNotEmpty) {
            profileUsername = uName;
          }

          final String av = (pMap['avatar_url'] ??
                  pMap['avatar_path'] ??
                  d['avatar_url'] ??
                  d['avatar_path'] ??
                  '')
              .toString()
              .trim();
          profileAvatar = av.isNotEmpty ? av : null;
        }
      }

      String kycStatus = baseUser.identityVerificationStatus;
      final kycRes = responses[2];
      if (kycRes.statusCode == 200) {
        final body = json.decode(kycRes.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          final vMap = d['verification'] is Map
              ? Map<String, dynamic>.from(d['verification'] as Map)
              : Map<String, dynamic>.from(d);
          final String s =
              (vMap['status'] ?? d['status'] ?? '').toString().trim();
          if (s.isNotEmpty) {
            kycStatus = s;
          }
        }
      }

      final updated = baseUser.copyWith(
        username: profileUsername,
        avatarPath: profileAvatar,
        clearAvatar: hasProfileResponse && profileAvatar == null,
        identityVerificationStatus: kycStatus,
      );

      state = state.copyWith(user: updated);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('storkia_auth_user', json.encode(updated.toJson()));
    } catch (_) {}
  }

  Future<void> logout() async {
    final token = state.token;
    if (token != null && token.isNotEmpty) {
      await ApiService.logout(token);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('storkia_auth_token');
      await prefs.remove('storkia_auth_user');
    }
    state = state.copyWith(clearAuth: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
