import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product_model.dart';

class RecentlyViewedService {
  static const String _key = 'storkia_recently_viewed';

  static Future<void> add(Product product) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> items = prefs.getStringList(_key) ?? [];

    items.removeWhere((item) {
      try {
        final p = Product.fromJson(json.decode(item));
        return p.id == product.id;
      } catch (_) {
        return false;
      }
    });

    items.insert(0, json.encode(product.toJson()));

    if (items.length > 20) {
      items = items.sublist(0, 20);
    }

    await prefs.setStringList(_key, items);
  }

  static Future<List<Product>> getProducts() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> items = prefs.getStringList(_key) ?? [];
    final List<Product> products = [];

    for (final String item in items) {
      try {
        products.add(Product.fromJson(json.decode(item)));
      } catch (_) {}
    }

    return products;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
