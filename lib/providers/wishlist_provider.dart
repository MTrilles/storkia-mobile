import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/product_model.dart';

typedef JsonMap = Map<String, dynamic>;

class WishlistState {
  final List<Product> items;
  final Set<int> productIds;
  final bool isLoading;

  const WishlistState({
    this.items = const [],
    this.productIds = const {},
    this.isLoading = false,
  });

  Set<int> get wishlistedIds => productIds;

  bool isWishlisted(int productId) => productIds.contains(productId);

  WishlistState copyWith({
    List<Product>? items,
    Set<int>? productIds,
    bool? isLoading,
  }) {
    final resolvedItems = items ?? this.items;
    final resolvedIds = productIds ?? {for (final p in resolvedItems) p.id};
    return WishlistState(
      items: resolvedItems,
      productIds: resolvedIds,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class WishlistNotifier extends StateNotifier<WishlistState> {
  WishlistNotifier() : super(const WishlistState());

  List<Product> _extractWishlistProducts(dynamic raw) {
    List<dynamic> list = [];
    if (raw is List) {
      list = raw;
    } else if (raw is Map) {
      for (final key in ['wishlist', 'items', 'products', 'data']) {
        final candidate = raw[key];
        if (candidate is List) {
          list = candidate;
          break;
        } else if (candidate is Map && candidate['data'] is List) {
          list = candidate['data'] as List<dynamic>;
          break;
        }
      }
    }

    final List<Product> parsed = [];
    for (final entry in list) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final JsonMap productMap = map['product'] is Map
          ? Map<String, dynamic>.from(map['product'] as Map)
          : map;
      productMap['is_wishlisted'] = true;
      if (map['is_unavailable'] == true) {
        productMap['is_unavailable'] = true;
      }
      if (map['is_sold_out'] == true) {
        productMap['is_sold_out'] = true;
      }
      final product = Product.fromJson(productMap);
      if (product.id > 0) {
        parsed.add(product);
      }
    }
    return parsed;
  }

  Future<void> fetchWishlist(
    String baseUrl,
    String token, {
    bool silent = false,
  }) async {
    if (token.isEmpty) return;
    final domain = ApiConfig.resolveBaseDomain(baseUrl);

    if (!silent && state.items.isEmpty) {
      state = state.copyWith(isLoading: true);
    }

    try {
      final response = await http.get(
        Uri.parse('$domain/api/v1/wishlist'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final products = _extractWishlistProducts(
          body is Map ? (body['data'] ?? body) : body,
        );
        state = state.copyWith(
          items: products,
          productIds: {for (final p in products) p.id},
          isLoading: false,
        );
        return;
      }
    } catch (_) {}

    if (state.isLoading) {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<String?> toggleWishlist(
    String baseUrl,
    String token,
    Product product,
  ) async {
    final domain = ApiConfig.resolveBaseDomain(baseUrl);
    final bool currentlyInWishlist = state.isWishlisted(product.id);

    if (currentlyInWishlist) {
      final nextItems = state.items.where((p) => p.id != product.id).toList();
      final nextIds = Set<int>.from(state.productIds)..remove(product.id);
      state = state.copyWith(items: nextItems, productIds: nextIds);
    } else {
      final nextItems = [
        product,
        ...state.items.where((p) => p.id != product.id),
      ];
      final nextIds = Set<int>.from(state.productIds)..add(product.id);
      state = state.copyWith(items: nextItems, productIds: nextIds);
    }

    try {
      final response = await http
          .post(
            Uri.parse('$domain/api/v1/wishlist/toggle'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'product_id': product.id}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data is Map) {
          if (data['is_wishlisted'] is bool) {
            final bool serverState = data['is_wishlisted'] as bool;
            if (!serverState) {
              final nextItems =
                  state.items.where((p) => p.id != product.id).toList();
              final nextIds = Set<int>.from(state.productIds)
                ..remove(product.id);
              state = state.copyWith(items: nextItems, productIds: nextIds);
            } else {
              final nextIds = Set<int>.from(state.productIds)..add(product.id);
              state = state.copyWith(productIds: nextIds);
            }
          }
          return data['message']?.toString() ??
              (currentlyInWishlist
                  ? 'Removed from Wish List'
                  : 'Added to Wish List');
        }
        return currentlyInWishlist
            ? 'Removed from Wish List'
            : 'Added to Wish List';
      }
    } catch (_) {}

    await fetchWishlist(domain, token, silent: true);
    return null;
  }

  Future<bool> removeFromWishlist(
    String baseUrl,
    String token,
    int productId,
  ) async {
    final domain = ApiConfig.resolveBaseDomain(baseUrl);
    final previousItems = List<Product>.from(state.items);
    final previousIds = Set<int>.from(state.productIds);

    final nextItems = state.items.where((p) => p.id != productId).toList();
    final nextIds = Set<int>.from(state.productIds)..remove(productId);
    state = state.copyWith(items: nextItems, productIds: nextIds);

    try {
      final response = await http.delete(
        Uri.parse('$domain/api/v1/wishlist/$productId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (response.statusCode == 200) {
        return true;
      }
    } catch (_) {}

    state = state.copyWith(items: previousItems, productIds: previousIds);
    return false;
  }
}

final wishlistProvider =
    StateNotifierProvider<WishlistNotifier, WishlistState>((ref) {
  return WishlistNotifier();
});
