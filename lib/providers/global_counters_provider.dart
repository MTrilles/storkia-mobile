import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/api_service.dart';

typedef JsonMap = Map<String, dynamic>;

class CartCountNotifier extends StateNotifier<int> {
  CartCountNotifier() : super(0);

  void updateCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> fetchCartCount(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/cart'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map) {
          final d = body['data'];
          if (d is List) {
            state = d.length;
          } else if (d is Map && d['items'] is List) {
            state = (d['items'] as List).length;
          } else if (body['count'] != null) {
            state = int.tryParse(body['count'].toString()) ?? 0;
          }
        }
      }
    } catch (_) {}
  }
}

class UnreadMessageNotifier extends StateNotifier<int> {
  UnreadMessageNotifier() : super(0);

  void updateCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> fetchUnreadCount(String token) async {
    if (token.isEmpty) return;
    try {
      final res = await ApiService.fetchUnreadMessageCount(token);
      if (res['success'] == true) {
        state = int.tryParse(res['count']?.toString() ?? '0') ?? 0;
      }
    } catch (_) {}
  }
}

class UnreadNotificationNotifier extends StateNotifier<int> {
  UnreadNotificationNotifier() : super(0);

  void updateCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> fetchUnreadCount(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications/unread-count'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map) {
          final d = body['data'];
          final rawCount = body['unread_count'] ??
              body['count'] ??
              (d is Map ? (d['unread_count'] ?? d['count']) : d);
          if (rawCount != null) {
            state = int.tryParse(rawCount.toString()) ?? 0;
            return;
          }
        }
      }
    } catch (_) {}
  }
}

class UnreadAnnouncementNotifier extends StateNotifier<int> {
  UnreadAnnouncementNotifier() : super(0);

  void updateCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> fetchUnreadCount(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/announcements/unread-count'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map) {
          final d = body['data'];
          final rawCount = body['unread_count'] ??
              body['count'] ??
              (d is Map ? (d['unread_count'] ?? d['count']) : d);
          if (rawCount != null) {
            state = int.tryParse(rawCount.toString()) ?? 0;
          }
        }
      }
    } catch (_) {}
  }
}

class RewardSummaryState {
  final bool isLoaded;
  final int coinsBalance;
  final double coinsPesoEquivalent;
  final int spinTickets;
  final bool canOpenChest;
  final int chestCooldownSec;
  final int dailySpinCooldownSec;
  final double walletAvailableBalance;
  final double walletPendingBalance;

  const RewardSummaryState({
    this.isLoaded = false,
    this.coinsBalance = 0,
    this.coinsPesoEquivalent = 0.0,
    this.spinTickets = 0,
    this.canOpenChest = false,
    this.chestCooldownSec = 0,
    this.dailySpinCooldownSec = 0,
    this.walletAvailableBalance = 0.0,
    this.walletPendingBalance = 0.0,
  });

  RewardSummaryState copyWith({
    bool? isLoaded,
    int? coinsBalance,
    double? coinsPesoEquivalent,
    int? spinTickets,
    bool? canOpenChest,
    int? chestCooldownSec,
    int? dailySpinCooldownSec,
    double? walletAvailableBalance,
    double? walletPendingBalance,
  }) {
    return RewardSummaryState(
      isLoaded: isLoaded ?? this.isLoaded,
      coinsBalance: coinsBalance ?? this.coinsBalance,
      coinsPesoEquivalent: coinsPesoEquivalent ?? this.coinsPesoEquivalent,
      spinTickets: spinTickets ?? this.spinTickets,
      canOpenChest: canOpenChest ?? this.canOpenChest,
      chestCooldownSec: chestCooldownSec ?? this.chestCooldownSec,
      dailySpinCooldownSec: dailySpinCooldownSec ?? this.dailySpinCooldownSec,
      walletAvailableBalance:
          walletAvailableBalance ?? this.walletAvailableBalance,
      walletPendingBalance: walletPendingBalance ?? this.walletPendingBalance,
    );
  }
}

class RewardSummaryNotifier extends StateNotifier<RewardSummaryState> {
  RewardSummaryNotifier() : super(const RewardSummaryState());

  Future<void> fetchRewardAndWalletSummary(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/rewards'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map && body['data'] is Map) {
          final data = Map<String, dynamic>.from(body['data'] as Map);
          final JsonMap wallet = data['wallet'] is Map
              ? Map<String, dynamic>.from(data['wallet'] as Map)
              : data;
          final JsonMap chest = data['chest'] is Map
              ? Map<String, dynamic>.from(data['chest'] as Map)
              : <String, dynamic>{};
          final JsonMap ewallet = data['buyer_ewallet'] is Map
              ? Map<String, dynamic>.from(data['buyer_ewallet'] as Map)
              : <String, dynamic>{};
          final JsonMap dailySpin = data['daily_spin'] is Map
              ? Map<String, dynamic>.from(data['daily_spin'] as Map)
              : <String, dynamic>{};

          final int coins = int.tryParse(
                  (wallet['coins_balance'] ?? data['coins_balance'] ?? '0')
                      .toString()) ??
              0;
          final int spins = int.tryParse(
                  (wallet['spin_tickets'] ?? data['spin_tickets'] ?? '0')
                      .toString()) ??
              0;
          final int chestSec = int.tryParse(
                  (chest['cooldown_sec'] ?? wallet['chest_cooldown_sec'] ?? '0')
                      .toString()) ??
              0;
          final bool canOpen = chest['can_open'] == true ||
              (chest.isEmpty && chestSec <= 0 && wallet.isNotEmpty);
          final int spinSec = int.tryParse((dailySpin['cooldown_sec'] ??
                      wallet['next_daily_spin_sec'] ??
                      '0')
                  .toString()) ??
              0;
          final double availBal = double.tryParse(
                  (ewallet['available_balance'] ??
                          data['wallet_available_balance'] ??
                          '0')
                      .toString()) ??
              0.0;
          final double pendBal = double.tryParse((ewallet['pending_balance'] ??
                      data['wallet_pending_balance'] ??
                      '0')
                  .toString()) ??
              0.0;

          state = RewardSummaryState(
            isLoaded: true,
            coinsBalance: coins,
            coinsPesoEquivalent: coins * 0.10,
            spinTickets: spins,
            canOpenChest: canOpen,
            chestCooldownSec: chestSec,
            dailySpinCooldownSec: spinSec,
            walletAvailableBalance: availBal,
            walletPendingBalance: pendBal,
          );
        }
      }
    } catch (_) {}
  }

  void applyChestOpened({
    int? coinsBalance,
    int? cooldownSec,
  }) {
    final int resolvedCoins = coinsBalance ?? state.coinsBalance;
    final int resolvedCooldown = cooldownSec ?? 86400;
    state = state.copyWith(
      isLoaded: true,
      coinsBalance: resolvedCoins,
      coinsPesoEquivalent: resolvedCoins * 0.10,
      canOpenChest: resolvedCooldown <= 0,
      chestCooldownSec: resolvedCooldown,
    );
  }

  void applyChestOpenedUpdate({
    required int coinsBalance,
    required int cooldownSec,
  }) {
    applyChestOpened(
      coinsBalance: coinsBalance,
      cooldownSec: cooldownSec,
    );
  }

  void applySpinOrRedeemUpdate({
    required int coinsBalance,
    int? spinTickets,
    int? dailySpinCooldownSec,
  }) {
    state = state.copyWith(
      isLoaded: true,
      coinsBalance: coinsBalance,
      coinsPesoEquivalent: coinsBalance * 0.10,
      spinTickets: spinTickets ?? state.spinTickets,
      dailySpinCooldownSec: dailySpinCooldownSec ?? state.dailySpinCooldownSec,
    );
  }
}

final cartCountProvider = StateNotifierProvider<CartCountNotifier, int>((ref) {
  return CartCountNotifier();
});

final unreadMessageProvider =
    StateNotifierProvider<UnreadMessageNotifier, int>((ref) {
  return UnreadMessageNotifier();
});

final unreadNotificationProvider =
    StateNotifierProvider<UnreadNotificationNotifier, int>((ref) {
  return UnreadNotificationNotifier();
});

final unreadAnnouncementProvider =
    StateNotifierProvider<UnreadAnnouncementNotifier, int>((ref) {
  return UnreadAnnouncementNotifier();
});

final rewardSummaryProvider =
    StateNotifierProvider<RewardSummaryNotifier, RewardSummaryState>((ref) {
  return RewardSummaryNotifier();
});

Future<void> syncAllBuyerCounters(WidgetRef ref, String token) async {
  if (token.isEmpty) return;
  await Future.wait([
    ref.read(cartCountProvider.notifier).fetchCartCount(token),
    ref.read(unreadMessageProvider.notifier).fetchUnreadCount(token),
    ref.read(unreadNotificationProvider.notifier).fetchUnreadCount(token),
    ref.read(unreadAnnouncementProvider.notifier).fetchUnreadCount(token),
    ref.read(rewardSummaryProvider.notifier).fetchRewardAndWalletSummary(token),
  ]);
}
