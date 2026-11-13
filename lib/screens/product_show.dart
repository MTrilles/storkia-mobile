import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../components/product_card.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/chat_models.dart';
import '../models/product_model.dart';
import '../models/seller_profile_model.dart';
import '../providers/global_counters_provider.dart';
import '../providers/wishlist_provider.dart';
import '../services/api_service.dart';
import '../services/recently_viewed_service.dart';
import 'cart_screen.dart';
import 'chat_screen.dart';
import 'checkout_screen.dart';
import 'seller_store_screen.dart';

typedef JsonMap = Map<String, dynamic>;
typedef StringMap = Map<String, String>;

class ProductShowScreen extends ConsumerStatefulWidget {
  final Product product;
  final String baseUrl;
  final String token;

  const ProductShowScreen({
    super.key,
    required this.product,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<ProductShowScreen> createState() => _ProductShowScreenState();
}

class _ProductShowScreenState extends ConsumerState<ProductShowScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  Timer? _autoSyncTimer;

  late Product _product;
  SellerProfile? _seller;
  JsonMap _storeStats = {
    'chat_response_rate': 98,
    'following': 0,
    'followers': 0,
    'ratings': '0.0',
    'total_ratings_count': 0,
    'joined': 'Recently',
    'products_count': 1,
  };
  JsonMap? _dealPricing;

  int? _selectedMainIndex;
  int? _selectedSubIndex;
  String _selectedMainName = '';
  String _selectedSubName = '';

  int _activeGalleryIndex = 0;
  bool _isViewingVariantImage = false;
  late String _currentImage;
  late double _activePrice;
  late int _activeStock;
  late int _totalStock;
  int _quantity = 1;

  late bool _hasVariants;
  bool _hasSubVariants = false;
  bool _isStoreOnVacation = false;
  bool _isOwnStore = false;
  bool _isFollowingStore = false;
  bool _isWishlisted = false;
  bool _hasRestockSubscription = false;
  bool _isSubscribingRestock = false;
  bool _isTogglingWishlist = false;
  bool _isTogglingFollow = false;
  int _perBuyerLimit = 0;

  double _productAvgRating = 0.0;
  int _totalSoldUnits = 0;
  int _selectedReviewStarFilter = 0;
  List<JsonMap> _storeVouchers = [];
  List<JsonMap> _reviews = [];
  List<JsonMap> _questions = [];
  List<Product> _recommendedProducts = [];

  bool _isLoadingDetails = true;
  bool _isAddingToCart = false;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _product = widget.product;
    _seller = widget.product.sellerProfile;
    _dealPricing = widget.product.dealPricing;
    _productAvgRating = widget.product.avgRating;
    _totalSoldUnits = widget.product.soldCount;
    _perBuyerLimit = widget.product.perBuyerLimit;
    _isStoreOnVacation = widget.product.isStoreOnVacation;
    _isWishlisted = widget.product.isWishlisted;

    RecentlyViewedService.add(_product);

    _currentImage = _product.pictures.isNotEmpty
        ? ApiConfig.storageUrl(_product.pictures.first, _domain)
        : '';
    _activePrice = _product.price;
    _hasVariants = _product.variants != null &&
        _product.variants!['items'] is List &&
        (_product.variants!['items'] as List).isNotEmpty;

    _totalStock = _calculateTotalStock(_product);
    _activeStock = _totalStock;

    _fetchFullProductDetails(silent: false);
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _fetchFullProductDetails(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchFullProductDetails(silent: true);
    }
  }

  int _calculateTotalStock(Product prod) {
    if (prod.variants != null &&
        prod.variants!['items'] is List &&
        (prod.variants!['items'] as List).isNotEmpty) {
      int total = 0;
      for (final item in (prod.variants!['items'] as List)) {
        if (item is! Map) continue;
        if (item['is_archived'] == true ||
            item['status']?.toString() == 'Disapproved') {
          continue;
        }
        if (item['subs'] is List && (item['subs'] as List).isNotEmpty) {
          for (final sub in (item['subs'] as List)) {
            if (sub is! Map) continue;
            if (sub['is_archived'] == true ||
                sub['status']?.toString() == 'Disapproved') {
              continue;
            }
            total += int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
          }
        } else {
          total += int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
        }
      }
      return total;
    }
    return prod.stockQuantity;
  }

  int get _maxAllowedQuantity {
    if (_perBuyerLimit > 0 && _activeStock > 0) {
      return _activeStock < _perBuyerLimit ? _activeStock : _perBuyerLimit;
    }
    return _activeStock > 0 ? _activeStock : 1;
  }

  double get _effectiveDiscountPercent {
    if (_dealPricing != null && _dealPricing!['has_promo'] == true) {
      final dealVar = _dealPricing!['variant_name']?.toString() ?? '';
      final dealSub = _dealPricing!['sub_variant_name']?.toString() ?? '';
      final bool matchesSelection = (dealVar.isEmpty ||
              _selectedMainName.isEmpty ||
              dealVar.toLowerCase() == _selectedMainName.toLowerCase()) &&
          (dealSub.isEmpty ||
              _selectedSubName.isEmpty ||
              dealSub.toLowerCase() == _selectedSubName.toLowerCase());

      if (matchesSelection) {
        final pct = double.tryParse(
            _dealPricing!['discount_percentage']?.toString() ?? '0');
        if (pct != null && pct > 0) {
          return pct;
        }
      }
    }
    return _product.discount;
  }

  double get _discountedActivePrice {
    final pct = _effectiveDiscountPercent;
    if (pct > 0) {
      return _activePrice - (_activePrice * (pct / 100));
    }
    return _activePrice;
  }

  List<JsonMap> get _filteredReviews {
    if (_selectedReviewStarFilter == 0) return _reviews;
    return _reviews.where((r) {
      final stars = int.tryParse(r['rating']?.toString() ?? '5') ?? 5;
      return stars == _selectedReviewStarFilter;
    }).toList();
  }

  int _countReviewsByStar(int star) {
    return _reviews.where((r) {
      final s = int.tryParse(r['rating']?.toString() ?? '5') ?? 5;
      return s == star;
    }).length;
  }

  String _formatMoney(double value) {
    final parts = value.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  Future<void> _fetchFullProductDetails({bool silent = true}) async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/products/${_product.id}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true && body['data'] is Map) {
          final payload = JsonMap.from(body['data'] as Map);
          final prodJson = payload['product'] is Map
              ? JsonMap.from(payload['product'] as Map)
              : null;
          final sellerJson = payload['seller'] is Map
              ? JsonMap.from(payload['seller'] as Map)
              : null;

          setState(() {
            if (payload['deal_pricing'] is Map) {
              _dealPricing = JsonMap.from(payload['deal_pricing'] as Map);
            }
            if (prodJson != null) {
              _product = Product.fromJson(prodJson);
              _hasVariants = _product.variants != null &&
                  _product.variants!['items'] is List &&
                  (_product.variants!['items'] as List).isNotEmpty;
              _totalStock = _calculateTotalStock(_product);
              if (_selectedMainIndex == null) {
                _activePrice = _product.price;
                _activeStock = _totalStock;
              } else {
                _refreshSelectedVariantStockAndPrice();
              }
            }
            if (sellerJson != null) {
              _seller = SellerProfile.fromJson(sellerJson);
            }
            if (payload['stats'] is Map) {
              _storeStats = JsonMap.from(payload['stats'] as Map);
            }
            _productAvgRating = double.tryParse(
                    payload['product_avg_rating']?.toString() ?? '0') ??
                _product.avgRating;
            _totalSoldUnits =
                int.tryParse(payload['total_sold_units']?.toString() ?? '0') ??
                    _product.soldCount;
            _isOwnStore = payload['is_own_store'] == true;
            _isFollowingStore = payload['is_following_store'] == true;
            _isWishlisted = payload['is_wishlisted'] == true;
            _hasRestockSubscription =
                payload['has_restock_subscription'] == true;
            _isStoreOnVacation = payload['is_store_on_vacation'] == true ||
                (_seller?.isOnVacation ?? false);
            _perBuyerLimit =
                int.tryParse(payload['per_buyer_limit']?.toString() ?? '0') ??
                    _product.perBuyerLimit;

            if (payload['store_vouchers'] is List) {
              final List<dynamic> rawVouchers =
                  List<dynamic>.from(payload['store_vouchers'] as List);
              _storeVouchers = [
                for (final v in rawVouchers)
                  if (v is Map) JsonMap.from(v),
              ];
            }
            if (payload['reviews'] is List) {
              final List<dynamic> rawReviews =
                  List<dynamic>.from(payload['reviews'] as List);
              _reviews = [
                for (final r in rawReviews)
                  if (r is Map) JsonMap.from(r),
              ];
            }
            if (payload['questions'] is List) {
              final List<dynamic> rawQuestions =
                  List<dynamic>.from(payload['questions'] as List);
              _questions = [
                for (final q in rawQuestions)
                  if (q is Map) JsonMap.from(q),
              ];
            }
            if (payload['related_products'] is List) {
              final List<dynamic> rawRelated =
                  List<dynamic>.from(payload['related_products'] as List);
              _recommendedProducts = [
                for (final p in rawRelated)
                  if (p is Map) Product.fromJson(JsonMap.from(p)),
              ];
            }
            _isLoadingDetails = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoadingDetails = false);
    }
  }

  void _refreshSelectedVariantStockAndPrice() {
    if (!_hasVariants ||
        _selectedMainIndex == null ||
        _product.variants?['items'] is! List) {
      return;
    }
    final List<dynamic> items =
        List<dynamic>.from(_product.variants!['items'] as List);
    if (_selectedMainIndex! >= items.length ||
        items[_selectedMainIndex!] is! Map) {
      return;
    }
    final item = JsonMap.from(items[_selectedMainIndex!] as Map);
    final bool hasSubs =
        item['subs'] is List && (item['subs'] as List).isNotEmpty;

    if (hasSubs && _selectedSubIndex != null) {
      final List<dynamic> subs = List<dynamic>.from(item['subs'] as List);
      if (_selectedSubIndex! < subs.length && subs[_selectedSubIndex!] is Map) {
        final sub = JsonMap.from(subs[_selectedSubIndex!] as Map);
        _activePrice = double.tryParse(sub['price']?.toString() ?? '') ??
            double.tryParse(item['price']?.toString() ?? '') ??
            _product.price;
        _activeStock = int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
        return;
      }
    }

    if (item['price'] != null) {
      _activePrice =
          double.tryParse(item['price'].toString()) ?? _product.price;
    }
    if (hasSubs) {
      int parentStock = 0;
      for (final sub in (item['subs'] as List)) {
        if (sub is Map &&
            sub['is_archived'] != true &&
            sub['status']?.toString() != 'Disapproved') {
          parentStock += int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
        }
      }
      _activeStock = parentStock;
    } else {
      _activeStock = int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
    }
  }

  void _selectGalleryImage(int index) {
    if (index < 0 || index >= _product.pictures.length) return;
    setState(() {
      _activeGalleryIndex = index;
      _isViewingVariantImage = false;
      _currentImage = ApiConfig.storageUrl(_product.pictures[index], _domain);
    });
  }

  void _onMainVariantSelected(int index, JsonMap item) {
    setState(() {
      if (_selectedMainIndex == index) {
        _selectedMainIndex = null;
        _selectedSubIndex = null;
        _selectedMainName = '';
        _selectedSubName = '';
        _hasSubVariants = false;
        _activePrice = _product.price;
        _activeStock = _totalStock;
        _isViewingVariantImage = false;
        _currentImage = _product.pictures.isNotEmpty
            ? ApiConfig.storageUrl(
                _product.pictures[
                    _activeGalleryIndex.clamp(0, _product.pictures.length - 1)],
                _domain,
              )
            : '';
      } else {
        _selectedMainIndex = index;
        _selectedSubIndex = null;
        _selectedMainName = item['name']?.toString() ?? '';
        _selectedSubName = '';
        _hasSubVariants =
            item['subs'] is List && (item['subs'] as List).isNotEmpty;

        if (item['price'] != null) {
          _activePrice =
              double.tryParse(item['price'].toString()) ?? _product.price;
        }
        if (_hasSubVariants) {
          int parentStock = 0;
          for (final sub in (item['subs'] as List)) {
            if (sub is Map &&
                sub['is_archived'] != true &&
                sub['status']?.toString() != 'Disapproved') {
              parentStock += int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
            }
          }
          _activeStock = parentStock;
        } else {
          _activeStock = int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
        }
        if (item['image'] != null && item['image'].toString().isNotEmpty) {
          _currentImage =
              ApiConfig.storageUrl(item['image'].toString(), _domain);
          _isViewingVariantImage = true;
        }
      }
      _quantity = 1;
    });
  }

  void _onSubVariantSelected(int index, JsonMap sub, JsonMap parentItem) {
    setState(() {
      if (_selectedSubIndex == index) {
        _selectedSubIndex = null;
        _selectedSubName = '';
        _activePrice = double.tryParse(parentItem['price']?.toString() ?? '') ??
            _product.price;
        int parentStock = 0;
        for (final s in (parentItem['subs'] as List)) {
          if (s is Map) {
            parentStock += int.tryParse(s['stock']?.toString() ?? '0') ?? 0;
          }
        }
        _activeStock = parentStock;
      } else {
        _selectedSubIndex = index;
        _selectedSubName = sub['name']?.toString() ?? '';
        _activePrice = double.tryParse(sub['price']?.toString() ?? '') ??
            double.tryParse(parentItem['price']?.toString() ?? '') ??
            _product.price;
        _activeStock = int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
        if (sub['image'] != null && sub['image'].toString().isNotEmpty) {
          _currentImage =
              ApiConfig.storageUrl(sub['image'].toString(), _domain);
          _isViewingVariantImage = true;
        }
      }
      _quantity = 1;
    });
  }

  Future<void> _subscribeRestock() async {
    if (_isSubscribingRestock) return;
    setState(() => _isSubscribingRestock = true);

    try {
      final response = await http
          .post(
            Uri.parse(
                '$_domain/api/v1/products/${_product.id}/restock-subscribe'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'variant_name':
                  _selectedMainName.isNotEmpty ? _selectedMainName : null,
              'sub_variant_name':
                  _selectedSubName.isNotEmpty ? _selectedSubName : null,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        setState(() => _hasRestockSubscription = true);
        _showToast(
          data['message']?.toString() ??
              'You will be notified when this item is back in stock!',
          isError: false,
        );
      } else {
        _showToast(
          data is Map
              ? (data['message']?.toString() ?? 'Unable to subscribe.')
              : 'Unable to subscribe.',
        );
      }
    } catch (_) {
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _isSubscribingRestock = false);
    }
  }

  void _openAskQuestionModal() {
    final questionCtrl = TextEditingController();
    bool isSubmitting = false;
    String? modalError;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Ask the Seller a Question',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const Text(
                      'Your question and the seller\'s official answer will be visible on this product page to help shoppers.',
                      style: TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: questionCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      onChanged: (_) {
                        if (modalError != null) {
                          setModalState(() => modalError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Type your question (5–500 characters) *',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                    ),
                    if (modalError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        modalError!,
                        style: const TextStyle(
                          color: StorkTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final qText = questionCtrl.text.trim();
                                if (qText.length < 5) {
                                  setModalState(() {
                                    modalError =
                                        'Question must be at least 5 characters.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
                                try {
                                  final response = await http
                                      .post(
                                        Uri.parse(
                                            '$_domain/api/v1/products/${_product.id}/questions'),
                                        headers: {
                                          'Authorization':
                                              'Bearer ${widget.token}',
                                          'Accept': 'application/json',
                                          'Content-Type': 'application/json',
                                        },
                                        body: json.encode({'question': qText}),
                                      )
                                      .timeout(ApiConfig.requestTimeout);

                                  final data = json.decode(response.body);
                                  if ((response.statusCode == 200 ||
                                          response.statusCode == 201) &&
                                      data is Map &&
                                      data['success'] == true) {
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    _showToast(
                                      data['message']?.toString() ??
                                          'Question posted!',
                                      isError: false,
                                    );
                                    _fetchFullProductDetails(silent: true);
                                  } else {
                                    setModalState(() {
                                      modalError = data is Map
                                          ? (data['message']?.toString() ??
                                              'Unable to post question.')
                                          : 'Unable to post question.';
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSubmitting = false);
                                  }
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Post Question'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _toggleReviewHelpful(int reviewId) async {
    final index = _reviews.indexWhere(
        (r) => (int.tryParse(r['id']?.toString() ?? '0') ?? 0) == reviewId);
    if (index < 0) return;

    final rev = _reviews[index];
    final bool wasUpvoted = rev['is_upvoted'] == true;
    final int prevCount =
        int.tryParse(rev['helpful_count']?.toString() ?? '0') ?? 0;

    setState(() {
      _reviews[index]['is_upvoted'] = !wasUpvoted;
      _reviews[index]['helpful_count'] =
          !wasUpvoted ? (prevCount + 1) : (prevCount > 0 ? prevCount - 1 : 0);
    });

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/reviews/$reviewId/helpful'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data is Map && data['success'] == true) {
          setState(() {
            _reviews[index]['is_upvoted'] = data['upvoted'] == true;
            if (data['helpful_count'] != null) {
              _reviews[index]['helpful_count'] =
                  int.tryParse(data['helpful_count'].toString()) ?? 0;
            }
          });
        }
      }
    } catch (_) {
      _fetchFullProductDetails(silent: true);
    }
  }

  Future<void> _toggleWishlist() async {
    if (_isTogglingWishlist) return;
    setState(() {
      _isTogglingWishlist = true;
      _isWishlisted = !_isWishlisted;
    });

    final msg = await ref
        .read(wishlistProvider.notifier)
        .toggleWishlist(_domain, widget.token, _product);

    if (!mounted) return;
    setState(() => _isTogglingWishlist = false);
    if (msg != null && msg.isNotEmpty) {
      _showToast(msg, isError: false);
    }
  }

  Future<void> _toggleFollowStore() async {
    if (_seller == null || _isTogglingFollow || _isOwnStore) return;
    setState(() => _isTogglingFollow = true);

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/sellers/${_seller!.id}/follow'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _isFollowingStore = data['is_following'] == true;
          _storeStats['followers'] =
              data['followers_count'] ?? _storeStats['followers'];
        });
        _showToast(data['message']?.toString() ?? 'Updated follow status.',
            isError: false);
      } else {
        _showToast(data['message']?.toString() ?? 'Unable to follow store.');
      }
    } catch (_) {
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  Future<void> _claimStoreVoucher(String code) async {
    if (_seller == null) return;
    try {
      final response = await http
          .post(
            Uri.parse('$_domain/api/v1/vouchers/claim'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'code': code,
              'seller_profile_id': _seller!.id,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        setState(() {
          for (final v in _storeVouchers) {
            if (v['code']?.toString().toUpperCase() == code.toUpperCase()) {
              v['is_claimed'] = true;
            }
          }
        });
        _showToast(
            data['message']?.toString() ??
                'Voucher "$code" claimed to your wallet!',
            isError: false);
      } else {
        _showToast(data['message']?.toString() ?? 'Unable to claim voucher.');
      }
    } catch (_) {
      _showToast('Network error occurred.');
    }
  }

  bool _validateBeforePurchase() {
    if (_isStoreOnVacation) {
      _showToast(
          'This store is currently on vacation and is temporarily not accepting orders.');
      return false;
    }
    if (_activeStock <= 0) {
      _showToast(
          'This product or selected variation is currently out of stock.');
      return false;
    }
    if (_hasVariants && _selectedMainName.isEmpty) {
      _showToast(
          'Please select a ${_product.variants?['title'] ?? 'variation'} first.');
      return false;
    }
    if (_hasSubVariants && _selectedSubName.isEmpty) {
      _showToast(
          'Please select a ${_product.variants?['sub_title'] ?? 'sub-variation'} too.');
      return false;
    }
    if (_perBuyerLimit > 0 && _quantity > _perBuyerLimit) {
      _showToast(
          'Purchase limit reached: You can buy at most $_perBuyerLimit unit(s) of this item.');
      return false;
    }
    if (_quantity > _activeStock) {
      _showToast('Only $_activeStock piece(s) available in stock.');
      return false;
    }
    return true;
  }

  Future<void> _addToCart() async {
    if (!_validateBeforePurchase()) return;

    setState(() => _isAddingToCart = true);
    try {
      final response = await http
          .post(
            Uri.parse('$_domain/api/v1/cart'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'product_id': _product.id,
              'quantity': _quantity,
              'variant':
                  _selectedMainName.isNotEmpty ? _selectedMainName : null,
              'sub_variant':
                  _selectedSubName.isNotEmpty ? _selectedSubName : null,
            }),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 || response.statusCode == 201) {
        ref.read(cartCountProvider.notifier).fetchCartCount(widget.token);
        _showToast('Product added to your shopping cart!', isError: false);
      } else {
        _showToast(
            data['message']?.toString() ?? 'Failed to add product to cart.');
      }
    } catch (_) {
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _isAddingToCart = false);
    }
  }

  void _buyNow() {
    if (!_validateBeforePurchase()) return;

    Navigator.push(
      context,
      StorkRoute.fade(
        CheckoutScreen(
          baseUrl: _domain,
          token: widget.token,
          mode: 'buy_now',
          buyNowData: {
            'product_id': _product.id,
            'quantity': _quantity,
            'variant': _selectedMainName.isNotEmpty ? _selectedMainName : null,
            'sub_variant':
                _selectedSubName.isNotEmpty ? _selectedSubName : null,
          },
        ),
      ),
    );
  }

  Future<void> _chatNowAboutProduct() async {
    final sellerUserId = _seller?.userId ?? _product.userId;
    if (sellerUserId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: StorkTheme.primary),
      ),
    );

    try {
      final userRes = await http.get(
        Uri.parse('$_domain/api/v1/user'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (userRes.statusCode == 200) {
        final userData = jsonDecode(userRes.body);
        final int authUserId =
            int.tryParse(userData['data']?['id']?.toString() ?? '0') ?? 0;

        final contactRes = await ApiService.fetchContacts(
          widget.token,
          contactId: sellerUserId,
        );

        if (!mounted) return;
        Navigator.pop(context);

        if (contactRes['success'] == true) {
          final List<ChatContact> contacts =
              List<ChatContact>.from(contactRes['data'] as List);
          if (contacts.isNotEmpty) {
            final contact = contacts.firstWhere(
              (c) => c.id == sellerUserId,
              orElse: () => contacts.first,
            );
            Navigator.push(
              context,
              StorkRoute.fade(
                ChatScreen(
                  contact: contact,
                  token: widget.token,
                  authUserId: authUserId,
                ),
              ),
            );
            return;
          }
        }
      } else {
        Navigator.pop(context);
      }
      _showToast('Unable to open seller chat right now.');
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showToast('Error connecting to chat.');
    }
  }

  void _showEditReviewBottomSheet(JsonMap rev) {
    int editRating = int.tryParse(rev['rating']?.toString() ?? '5') ?? 5;
    final textCtrl =
        TextEditingController(text: rev['review_text']?.toString() ?? '');
    List<XFile> pickedPhotos = [];
    String? modalError;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: StorkTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 14,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: StorkTheme.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Edit Your Review (1-Time Edit)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: StorkTheme.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(modalContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      children: List.generate(5, (i) {
                        final star = i + 1;
                        return IconButton(
                          onPressed: () =>
                              setModalState(() => editRating = star),
                          icon: Icon(
                            star <= editRating
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            color: Colors.amber,
                            size: 30,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      onChanged: (_) {
                        if (modalError != null) {
                          setModalState(() => modalError = null);
                        }
                      },
                      decoration: const InputDecoration(
                        labelText: 'Update Review Comment',
                        fillColor: StorkTheme.surfaceSubtle,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final files = await picker.pickMultiImage(
                          imageQuality: 82,
                        );
                        if (files.isNotEmpty) {
                          final valid = <XFile>[];
                          for (final f in files.take(5)) {
                            final len = await f.length();
                            if (len > 5 * 1024 * 1024) {
                              setModalState(() {
                                modalError =
                                    'Each review photo must not exceed 5MB.';
                              });
                              continue;
                            }
                            valid.add(f);
                          }
                          setModalState(() {
                            pickedPhotos = valid;
                          });
                        }
                      },
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: Text(pickedPhotos.isEmpty
                          ? 'Replace Review Photos (Max 5)'
                          : '${pickedPhotos.length} photo(s) selected'),
                    ),
                    if (pickedPhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(pickedPhotos.length, (pIdx) {
                          return Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(pickedPhotos[pIdx].path),
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    pickedPhotos.removeAt(pIdx);
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                    if (modalError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        modalError!,
                        style: const TextStyle(
                          color: StorkTheme.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving
                            ? null
                            : () async {
                                setModalState(() {
                                  isSaving = true;
                                  modalError = null;
                                });
                                try {
                                  final req = http.MultipartRequest(
                                    'POST',
                                    Uri.parse(
                                        '$_domain/api/v1/reviews/${rev['id']}'),
                                  );
                                  req.headers['Authorization'] =
                                      'Bearer ${widget.token}';
                                  req.headers['Accept'] = 'application/json';
                                  req.fields['rating'] = '$editRating';
                                  req.fields['review_text'] =
                                      textCtrl.text.trim();

                                  for (final f in pickedPhotos) {
                                    req.files.add(
                                      await http.MultipartFile.fromPath(
                                        'review_photos[]',
                                        f.path,
                                      ),
                                    );
                                  }

                                  final streamed = await req
                                      .send()
                                      .timeout(ApiConfig.requestTimeout);
                                  final res =
                                      await http.Response.fromStream(streamed);
                                  final data = json.decode(res.body);

                                  if (res.statusCode == 200 &&
                                      data['success'] == true) {
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    _showToast(
                                        data['message']?.toString() ??
                                            'Review updated!',
                                        isError: false);
                                    _fetchFullProductDetails(silent: true);
                                  } else {
                                    setModalState(() {
                                      modalError =
                                          data['message']?.toString() ??
                                              'Failed to update review.';
                                    });
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError = 'Network error occurred.';
                                  });
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(() => isSaving = false);
                                  }
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Updated Review'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showToast(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? StorkTheme.danger : StorkTheme.success,
      ),
    );
  }

  void _showImageZoomModal(String imageUrl) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black.withValues(alpha: 0.92),
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                minScale: 0.6,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Positioned(
                top: MediaQuery.of(dialogContext).padding.top + 12,
                right: 16,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                  ),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 26),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = ref.watch(cartCountProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final gridColumns = screenWidth >= 700 ? 3 : 2;
    final aspectRatio = screenWidth < 350 ? 0.63 : 0.68;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(
          _product.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                StorkRoute.fade(
                  CartScreen(
                    baseUrl: _domain,
                    token: widget.token,
                  ),
                ),
              );
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.shopping_bag_outlined, size: 23),
                if (cartCount > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4.5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: StorkTheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$cartCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        color: StorkTheme.primary,
        onRefresh: () => _fetchFullProductDetails(silent: true),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isStoreOnVacation)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: StorkTheme.warning.withValues(alpha: 0.14),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: StorkTheme.warning,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'ON VACATION',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_seller?.businessName ?? 'This store'} is currently on vacation. Add to Cart and Buy Now are temporarily paused.',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.textMain,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _buildImageGallerySection(),
                  const SizedBox(height: 10),
                  _buildPrimaryInfoSection(),
                  if (_storeVouchers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _buildStoreVouchersSection(),
                  ],
                  const SizedBox(height: 10),
                  _buildVariantsAndQuantitySection(),
                  if (_seller != null) ...[
                    const SizedBox(height: 10),
                    _buildSellerStoreCard(),
                  ],
                  const SizedBox(height: 10),
                  _buildSpecificationsAndDescriptionSection(),
                  const SizedBox(height: 10),
                  _buildProductQnaSection(),
                  const SizedBox(height: 10),
                  _buildReviewsSection(),
                  if (_recommendedProducts.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                      child: Text(
                        'Recommended Products You May Also Like',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_recommendedProducts.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: gridColumns,
                    childAspectRatio: aspectRatio,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return ProductCard(
                        product: _recommendedProducts[index],
                        baseUrl: _domain,
                        token: widget.token,
                      );
                    },
                    childCount: _recommendedProducts.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(),
    );
  }

  Widget _buildImageGallerySection() {
    return Container(
      decoration: const BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (_currentImage.isNotEmpty) {
                    _showImageZoomModal(_currentImage);
                  }
                },
                child: AspectRatio(
                  aspectRatio: 1,
                  child: _currentImage.isNotEmpty
                      ? Image.network(
                          _currentImage,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 64,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        )
                      : const Center(
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                ),
              ),
              if (_totalStock <= 0)
                Positioned(
                  top: 14,
                  left: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.78),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'SOLD OUT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: _isViewingVariantImage
                      ? GestureDetector(
                          onTap: () => _selectGalleryImage(_activeGalleryIndex),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              gradient: StorkTheme.brandGradient,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Text(
                              'Viewing Variant Photo (Tap for Main Gallery)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        )
                      : (_product.pictures.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Gallery ${_activeGalleryIndex + 1} / ${_product.pictures.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            )
                          : const SizedBox.shrink()),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.92),
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _toggleWishlist,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(
                        _isWishlisted
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _isWishlisted
                            ? StorkTheme.danger
                            : StorkTheme.textMuted,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_product.pictures.length > 1)
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                itemCount: _product.pictures.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final picUrl =
                      ApiConfig.storageUrl(_product.pictures[index], _domain);
                  final isSelected =
                      !_isViewingVariantImage && _activeGalleryIndex == index;
                  return GestureDetector(
                    onTap: () => _selectGalleryImage(index),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? StorkTheme.primary
                              : StorkTheme.borderSubtle,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(picUrl, fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryInfoSection() {
    final bool hasDeal =
        _dealPricing != null && _dealPricing!['has_promo'] == true;
    final double discountPct = _effectiveDiscountPercent;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasDeal) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                gradient: StorkTheme.brandGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '⚡ ${_dealPricing!['promo_label'] ?? 'SUPER DEAL ACTIVE'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (_dealPricing!['remaining_slot_stock'] != null)
                    Text(
                      '${_dealPricing!['remaining_slot_stock']} slot(s) left',
                      style: const TextStyle(
                        color: StorkTheme.brandLight,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                ],
              ),
            ),
          ],
          Text(
            _product.name,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: StorkTheme.textMain,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 3),
                  Text(
                    _productAvgRating.toStringAsFixed(1),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '(${_reviews.length} ratings)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                ],
              ),
              const Text('|', style: TextStyle(color: StorkTheme.borderSubtle)),
              Text(
                '$_totalSoldUnits Sold',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: StorkTheme.textMuted,
                ),
              ),
              if (_perBuyerLimit > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: StorkTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Max $_perBuyerLimit per buyer',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  StorkTheme.primary.withValues(alpha: 0.08),
                  StorkTheme.brandLight.withValues(alpha: 0.22),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: StorkTheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Text(
                  '₱${_formatMoney(_discountedActivePrice)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: StorkTheme.primary,
                  ),
                ),
                if (discountPct > 0) ...[
                  Text(
                    '₱${_formatMoney(_activePrice)}',
                    style: const TextStyle(
                      fontSize: 14,
                      decoration: TextDecoration.lineThrough,
                      color: StorkTheme.textMuted,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: StorkTheme.danger,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${discountPct.toStringAsFixed(0)}% OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreVouchersSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'STORE VOUCHERS (${_seller?.businessName ?? 'STORE'})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Claimable here only',
                style: TextStyle(fontSize: 11, color: StorkTheme.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 70,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _storeVouchers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final sv = _storeVouchers[index];
                final code = sv['code']?.toString() ?? '';
                final badge = sv['badge_label']?.toString() ?? 'DISCOUNT';
                final minSpend =
                    double.tryParse(sv['min_spend']?.toString() ?? '0') ?? 0;
                final isClaimed = sv['is_claimed'] == true;

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: StorkTheme.brandLight.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: StorkTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: StorkTheme.primaryDark,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                badge,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: StorkTheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Min. Spend ₱${minSpend.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed:
                            isClaimed ? null : () => _claimStoreVoucher(code),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          minimumSize: const Size(0, 32),
                          backgroundColor: isClaimed
                              ? StorkTheme.borderSubtle
                              : StorkTheme.primary,
                        ),
                        child: Text(
                          isClaimed ? 'Claimed' : 'Claim',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVariantsAndQuantitySection() {
    final List<dynamic> rawVariantItems =
        (_hasVariants && _product.variants!['items'] is List)
            ? List<dynamic>.from(_product.variants!['items'] as List)
            : <dynamic>[];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasVariants) ...[
            Text(
              (_product.variants?['title'] ?? 'Variants')
                  .toString()
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(rawVariantItems.length, (index) {
                final item = rawVariantItems[index];
                if (item is! Map) return const SizedBox.shrink();
                if (item['is_archived'] == true ||
                    item['status']?.toString() == 'Disapproved') {
                  return const SizedBox.shrink();
                }

                final hasSubs =
                    item['subs'] is List && (item['subs'] as List).isNotEmpty;
                int itemStock = 0;
                if (hasSubs) {
                  for (final s in (item['subs'] as List)) {
                    if (s is Map &&
                        s['is_archived'] != true &&
                        s['status']?.toString() != 'Disapproved') {
                      itemStock +=
                          int.tryParse(s['stock']?.toString() ?? '0') ?? 0;
                    }
                  }
                } else {
                  itemStock =
                      int.tryParse(item['stock']?.toString() ?? '0') ?? 0;
                }

                final isOut = itemStock <= 0 && !hasSubs;
                final isSelected = _selectedMainIndex == index;

                return GestureDetector(
                  onTap: () =>
                      _onMainVariantSelected(index, JsonMap.from(item)),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? StorkTheme.primary.withValues(alpha: 0.1)
                          : (isOut
                              ? StorkTheme.surfaceSubtle
                              : StorkTheme.surface),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? StorkTheme.primary
                            : StorkTheme.borderSubtle,
                        width: isSelected ? 1.6 : 1,
                      ),
                    ),
                    child: Text(
                      '${item['name'] ?? 'Option'}${isOut ? ' (Out)' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        decoration: isOut ? TextDecoration.lineThrough : null,
                        color: isSelected
                            ? StorkTheme.primary
                            : (isOut
                                ? StorkTheme.textMuted
                                : StorkTheme.textMain),
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 18),
          ],
          if (_hasSubVariants &&
              _selectedMainIndex != null &&
              rawVariantItems[_selectedMainIndex!] is Map) ...[
            Text(
              (_product.variants?['sub_title'] ?? 'Sub Variants')
                  .toString()
                  .toUpperCase(),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final parentItem =
                  JsonMap.from(rawVariantItems[_selectedMainIndex!] as Map);
              final List<dynamic> subs = parentItem['subs'] is List
                  ? List<dynamic>.from(parentItem['subs'] as List)
                  : <dynamic>[];
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(subs.length, (sIndex) {
                  final sub = subs[sIndex];
                  if (sub is! Map) return const SizedBox.shrink();
                  if (sub['is_archived'] == true ||
                      sub['status']?.toString() == 'Disapproved') {
                    return const SizedBox.shrink();
                  }
                  final int subStock =
                      int.tryParse(sub['stock']?.toString() ?? '0') ?? 0;
                  final bool isOut = subStock <= 0;
                  final bool isSelected = _selectedSubIndex == sIndex;

                  return GestureDetector(
                    onTap: () => _onSubVariantSelected(
                      sIndex,
                      JsonMap.from(sub),
                      parentItem,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? StorkTheme.primary.withValues(alpha: 0.1)
                            : (isOut
                                ? StorkTheme.surfaceSubtle
                                : StorkTheme.surface),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? StorkTheme.primary
                              : StorkTheme.borderSubtle,
                          width: isSelected ? 1.6 : 1,
                        ),
                      ),
                      child: Text(
                        '${sub['name'] ?? 'Option'}${isOut ? ' (Out)' : ''}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          decoration: isOut ? TextDecoration.lineThrough : null,
                          color: isSelected
                              ? StorkTheme.primary
                              : (isOut
                                  ? StorkTheme.textMuted
                                  : StorkTheme.textMain),
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
            const SizedBox(height: 18),
          ],
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 10,
            runSpacing: 8,
            children: [
              const Text(
                'QUANTITY',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primaryDark,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: StorkTheme.surfaceSubtle,
                      border: Border.all(color: StorkTheme.borderSubtle),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.remove_rounded, size: 16),
                          onPressed: _quantity > 1
                              ? () => setState(() => _quantity--)
                              : null,
                        ),
                        SizedBox(
                          width: 34,
                          child: Text(
                            '$_quantity',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.add_rounded, size: 16),
                          onPressed: _quantity < _maxAllowedQuantity
                              ? () => setState(() => _quantity++)
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _activeStock > 5
                          ? StorkTheme.surfaceSubtle
                          : StorkTheme.danger.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _activeStock > 0 ? '$_activeStock available' : 'Sold out',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _activeStock > 5
                            ? StorkTheme.textMuted
                            : StorkTheme.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_activeStock <= 0 && !_isOwnStore) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: (_hasRestockSubscription || _isSubscribingRestock)
                    ? null
                    : _subscribeRestock,
                icon: Icon(
                  _hasRestockSubscription
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_none_rounded,
                  size: 18,
                ),
                label: Text(
                  _hasRestockSubscription
                      ? '✓ Subscribed for Back-in-Stock Alert'
                      : (_isSubscribingRestock
                          ? 'Subscribing...'
                          : 'Notify Me When Back in Stock'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSellerStoreCard() {
    final seller = _seller!;
    final logoUrl = seller.logoPath != null
        ? ApiConfig.storageUrl(seller.logoPath, _domain)
        : '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    StorkRoute.fade(
                      SellerStoreScreen(
                        sellerProfile: seller,
                        baseUrl: _domain,
                        token: widget.token,
                      ),
                    ),
                  );
                },
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor:
                          StorkTheme.primary.withValues(alpha: 0.12),
                      backgroundImage:
                          logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null,
                      child: logoUrl.isEmpty
                          ? Text(
                              seller.businessName.isNotEmpty
                                  ? seller.businessName[0].toUpperCase()
                                  : 'S',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primary,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isStoreOnVacation
                              ? StorkTheme.warning
                              : StorkTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      seller.businessName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      seller.lineOfBusiness.isNotEmpty
                          ? '${seller.lineOfBusiness} • ${seller.municipality}, ${seller.province}'
                          : '${seller.municipality}, ${seller.province}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isOwnStore) ...[
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isTogglingFollow ? null : _toggleFollowStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFollowingStore
                        ? StorkTheme.surfaceSubtle
                        : StorkTheme.primary,
                    foregroundColor:
                        _isFollowingStore ? StorkTheme.textMain : Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(
                    _isFollowingStore ? 'Following' : '+ Follow (₱30 Off)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _chatNowAboutProduct,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                  label: const Text('Chat Now'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: StorkTheme.primary,
                    side: BorderSide(
                        color: StorkTheme.primary.withValues(alpha: 0.4)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      StorkRoute.fade(
                        SellerStoreScreen(
                          sellerProfile: seller,
                          baseUrl: _domain,
                          token: widget.token,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.storefront_outlined, size: 17),
                  label: const Text('View Store'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: StorkTheme.surfaceSubtle,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: _buildStoreStatItem('Chat Rate',
                      '${_storeStats['chat_response_rate'] ?? 98}%'),
                ),
                Expanded(
                  child: _buildStoreStatItem(
                      'Followers', '${_storeStats['followers'] ?? 0}'),
                ),
                Expanded(
                  child: _buildStoreStatItem(
                      'Rating', '${_storeStats['ratings'] ?? '0.0'} ★'),
                ),
                Expanded(
                  child: _buildStoreStatItem(
                      'Products', '${_storeStats['products_count'] ?? 1}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: StorkTheme.primaryDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10.5,
            color: StorkTheme.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildSpecificationsAndDescriptionSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PRODUCT SPECIFICATIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          for (final spec in _product.specifications)
            _buildSpecRow(spec.title, spec.description),
          _buildSpecRow('Weight', '${_product.weight} kg'),
          _buildSpecRow('Stock', '$_activeStock'),
          _buildSpecRow(
            'Ships From',
            _seller != null
                ? '${_seller!.municipality}, ${_seller!.province}'
                : 'Local Warehouse',
          ),
          const Divider(height: 28),
          const Text(
            'PRODUCT DESCRIPTION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _product.description.isNotEmpty
                ? _product.description
                : 'No description provided.',
            style: const TextStyle(
              fontSize: 13.5,
              color: StorkTheme.textMain,
              height: 1.5,
            ),
          ),
          if (_product.additionalDescriptions != null &&
              _product.additionalDescriptions!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _product.additionalDescriptions!,
              style: const TextStyle(
                fontSize: 13.5,
                color: StorkTheme.textMain,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: StorkTheme.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: StorkTheme.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductQnaSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'BUYER PRODUCT Q&A (${_questions.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              if (!_isOwnStore)
                TextButton.icon(
                  onPressed: _openAskQuestionModal,
                  icon: const Icon(Icons.help_outline_rounded, size: 16),
                  label: const Text(
                    'Ask Question',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_questions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No questions asked about this product yet. Tap "Ask Question" to ask the seller!',
                style: TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _questions.length,
              separatorBuilder: (_, __) => const Divider(height: 20),
              itemBuilder: (context, index) {
                final q = _questions[index];
                final String? answer = q['answer']?.toString();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Q by ${q['buyer_name'] ?? 'Buyer'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          q['created_at']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 11,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      q['question']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: StorkTheme.textMain,
                      ),
                    ),
                    if (answer != null && answer.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: StorkTheme.brandLight.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StorkTheme.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OFFICIAL STORE ANSWER (${_seller?.businessName ?? 'Seller'})',
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              answer,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Awaiting seller response...',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    final visibleReviews = _filteredReviews;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
        boxShadow: StorkTheme.softCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'VERIFIED BUYER RATINGS (${_reviews.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                '${_productAvgRating.toStringAsFixed(1)} / 5.0 ★',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: StorkTheme.primary,
                ),
              ),
            ],
          ),
          if (_reviews.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildReviewFilterChip(
                    label: 'All (${_reviews.length})',
                    isSelected: _selectedReviewStarFilter == 0,
                    onTap: () => setState(() => _selectedReviewStarFilter = 0),
                  ),
                  for (int star = 5; star >= 1; star--)
                    _buildReviewFilterChip(
                      label: '$star ★ (${_countReviewsByStar(star)})',
                      isSelected: _selectedReviewStarFilter == star,
                      onTap: () =>
                          setState(() => _selectedReviewStarFilter = star),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_isLoadingDetails && _reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: StorkTheme.primary),
              ),
            )
          else if (visibleReviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _selectedReviewStarFilter == 0
                    ? 'No buyer ratings submitted for this product yet. Complete an order to leave the first review and earn up to +10 Storkia Coins!'
                    : 'No $_selectedReviewStarFilter-star reviews found for this filter.',
                style: const TextStyle(
                    fontSize: 12.5, color: StorkTheme.textMuted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleReviews.length,
              separatorBuilder: (_, __) => const Divider(height: 24),
              itemBuilder: (context, index) {
                final rev = visibleReviews[index];
                final int reviewId =
                    int.tryParse(rev['id']?.toString() ?? '0') ?? 0;
                final int rating =
                    int.tryParse(rev['rating']?.toString() ?? '5') ?? 5;
                final List<dynamic> photos = rev['review_photos'] is List
                    ? List<dynamic>.from(rev['review_photos'] as List)
                    : <dynamic>[];
                final bool canEdit = rev['can_edit'] == true;
                final bool isEdited = rev['edited_at'] != null;
                final String? purchasedVariant =
                    rev['purchased_variant_label']?.toString();
                final int helpfulCount =
                    int.tryParse(rev['helpful_count']?.toString() ?? '0') ?? 0;
                final bool isUpvoted = rev['is_upvoted'] == true;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Text(
                                rev['buyer_name']?.toString() ??
                                    'Verified Buyer',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < rating
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    size: 14,
                                    color: Colors.amber,
                                  ),
                                ),
                              ),
                              if (purchasedVariant != null &&
                                  purchasedVariant.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: StorkTheme.brandLight
                                        .withValues(alpha: 0.45),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Variation: $purchasedVariant',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: StorkTheme.primaryDark,
                                    ),
                                  ),
                                ),
                              if (isEdited)
                                const Text(
                                  '(Edited)',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              rev['created_at_human']?.toString() ?? '',
                              style: const TextStyle(
                                fontSize: 11,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                            if (canEdit) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _showEditReviewBottomSheet(rev),
                                child: const Text(
                                  'Edit',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    if (rev['review_text'] != null &&
                        rev['review_text'].toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        rev['review_text'].toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: StorkTheme.textMain,
                          height: 1.4,
                        ),
                      ),
                    ],
                    if (photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: photos.map((p) {
                          final photoUrl =
                              ApiConfig.storageUrl(p.toString(), _domain);
                          return GestureDetector(
                            onTap: () => _showImageZoomModal(photoUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(
                                photoUrl,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        InkWell(
                          onTap: reviewId > 0
                              ? () => _toggleReviewHelpful(reviewId)
                              : null,
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isUpvoted
                                  ? StorkTheme.primary.withValues(alpha: 0.12)
                                  : StorkTheme.surfaceSubtle,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isUpvoted
                                    ? StorkTheme.primary
                                    : StorkTheme.borderSubtle,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isUpvoted
                                      ? Icons.thumb_up_alt_rounded
                                      : Icons.thumb_up_off_alt_rounded,
                                  size: 13,
                                  color: isUpvoted
                                      ? StorkTheme.primary
                                      : StorkTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  helpfulCount > 0
                                      ? 'Helpful ($helpfulCount)'
                                      : 'Helpful',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isUpvoted
                                        ? StorkTheme.primary
                                        : StorkTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (rev['seller_reply'] != null &&
                        rev['seller_reply'].toString().trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StorkTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: StorkTheme.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "SELLER'S RESPONSE (${_seller?.businessName ?? 'Official Store'})",
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: StorkTheme.primaryDark,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              rev['seller_reply'].toString(),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: StorkTheme.textMain,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReviewFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: isSelected ? StorkTheme.brandGradient : null,
          color: isSelected ? null : StorkTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? StorkTheme.primary : StorkTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : StorkTheme.textMain,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    final bool isDisabled = _isStoreOnVacation || _activeStock <= 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        border: const Border(top: BorderSide(color: StorkTheme.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_isAddingToCart || isDisabled) ? null : _addToCart,
                icon: _isAddingToCart
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: StorkTheme.primary,
                        ),
                      )
                    : const Icon(Icons.add_shopping_cart_rounded, size: 19),
                label: Text(
                  _isStoreOnVacation
                      ? 'On Vacation'
                      : (_activeStock <= 0
                          ? 'Sold Out'
                          : (_isAddingToCart ? 'Adding...' : 'Add To Cart')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: StorkTheme.primary,
                  backgroundColor: StorkTheme.primary.withValues(alpha: 0.08),
                  side: BorderSide(
                    color: isDisabled
                        ? StorkTheme.borderSubtle
                        : StorkTheme.primary.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  gradient: (_isAddingToCart || isDisabled)
                      ? null
                      : StorkTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  onPressed: (_isAddingToCart || isDisabled) ? null : _buyNow,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _isStoreOnVacation
                        ? 'Store On Vacation'
                        : (_activeStock <= 0 ? 'Sold Out' : 'Buy Now'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
