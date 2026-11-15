import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';

class CartCountNotifier extends StateNotifier<int> {
  CartCountNotifier() : super(0);

  void updateCount(int count) {
    state = count < 0 ? 0 : count;
  }

  Future<void> fetchCartCount(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/cart'),
            headers: ApiService.buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

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
      final response = await ApiService.httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/notifications/unread-count'),
            headers: ApiService.buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

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
      final response = await ApiService.httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/announcements/unread-count'),
            headers: ApiService.buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

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

class OrderCountsState {
  final int all;
  final int unpaid;
  final int processing;
  final int shipped;
  final int toConfirm;
  final int toRate;
  final int completed;
  final int returns;

  const OrderCountsState({
    this.all = 0,
    this.unpaid = 0,
    this.processing = 0,
    this.shipped = 0,
    this.toConfirm = 0,
    this.toRate = 0,
    this.completed = 0,
    this.returns = 0,
  });

  int countForTab(String key) {
    switch (key) {
      case 'all':
        return all;
      case 'unpaid':
        return unpaid;
      case 'processing':
        return processing;
      case 'shipped':
        return shipped;
      case 'to_confirm':
        return toConfirm;
      case 'to_rate':
        return toRate;
      case 'completed':
        return completed;
      case 'returns':
        return returns;
      default:
        return 0;
    }
  }

  Map<String, int> toMap() => {
        'all': all,
        'unpaid': unpaid,
        'processing': processing,
        'shipped': shipped,
        'to_confirm': toConfirm,
        'to_rate': toRate,
        'completed': completed,
        'returns': returns,
      };

  factory OrderCountsState.fromMap(Map<dynamic, dynamic> map) {
    int parseKey(String k) => int.tryParse(map[k]?.toString() ?? '0') ?? 0;
    return OrderCountsState(
      all: parseKey('all'),
      unpaid: parseKey('unpaid'),
      processing: parseKey('processing'),
      shipped: parseKey('shipped'),
      toConfirm: parseKey('to_confirm'),
      toRate: parseKey('to_rate'),
      completed: parseKey('completed'),
      returns: parseKey('returns'),
    );
  }
}

class OrderCountsNotifier extends StateNotifier<OrderCountsState> {
  OrderCountsNotifier() : super(const OrderCountsState());

  void updateFromMap(Map<dynamic, dynamic> rawCounts) {
    state = OrderCountsState.fromMap(rawCounts);
  }

  Future<void> fetchOrderCounts(String token) async {
    if (token.isEmpty) return;
    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/orders?per_page=1'),
            headers: ApiService.buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map && body['counts'] is Map) {
          state = OrderCountsState.fromMap(body['counts'] as Map);
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
      final response = await ApiService.httpClient
          .get(
            Uri.parse('${ApiConfig.baseUrl}/rewards'),
            headers: ApiService.buildHeaders(token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body is Map && body['data'] is Map) {
          final data = JsonMap.from(body['data'] as Map);
          final JsonMap wallet = data['wallet'] is Map
              ? JsonMap.from(data['wallet'] as Map)
              : data;
          final JsonMap chest = data['chest'] is Map
              ? JsonMap.from(data['chest'] as Map)
              : <String, dynamic>{};
          final JsonMap ewallet = data['buyer_ewallet'] is Map
              ? JsonMap.from(data['buyer_ewallet'] as Map)
              : <String, dynamic>{};
          final JsonMap dailySpin = data['daily_spin'] is Map
              ? JsonMap.from(data['daily_spin'] as Map)
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

final orderCountsProvider =
    StateNotifierProvider<OrderCountsNotifier, OrderCountsState>((ref) {
  return OrderCountsNotifier();
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
    ref.read(orderCountsProvider.notifier).fetchOrderCounts(token),
    ref.read(rewardSummaryProvider.notifier).fetchRewardAndWalletSummary(token),
  ]);
}
