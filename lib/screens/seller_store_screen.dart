import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../components/product_card.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/chat_models.dart';
import '../models/product_model.dart';
import '../models/seller_profile_model.dart';
import '../services/api_service.dart';
import 'chat_screen.dart';

typedef JsonMap = Map<String, dynamic>;

class SellerStoreScreen extends StatefulWidget {
  final SellerProfile sellerProfile;
  final String baseUrl;
  final String token;

  const SellerStoreScreen({
    super.key,
    required this.sellerProfile,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<SellerStoreScreen> createState() => _SellerStoreScreenState();
}

class _SellerStoreScreenState extends State<SellerStoreScreen>
    with WidgetsBindingObserver {
  late SellerProfile _seller;
  Timer? _autoSyncTimer;

  JsonMap _stats = {
    'chat_response_rate': 98,
    'following': 0,
    'followers': 0,
    'ratings': '0.0',
    'total_ratings_count': 0,
    'joined': 'Recently',
    'products_count': 0,
  };

  bool _isFollowing = false;
  bool _isOwnStore = false;
  bool _isTogglingFollow = false;
  bool _isLoadingStore = true;

  List<Product> _allProducts = [];
  List<String> _mainCategories = [];
  List<String> _subCategories = [];
  List<JsonMap> _storeVouchers = [];

  String _searchQuery = '';
  String _selectedMainCategory = '';
  String _selectedSubCategory = '';
  String _sortBy = 'newest';

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seller = widget.sellerProfile;
    _isFollowing = _seller.isFollowing;
    _isOwnStore = _seller.isOwnStore;
    if (_seller.stats != null) {
      _stats = Map<String, dynamic>.from(_seller.stats!);
    }
    _fetchStoreData();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _fetchStoreData(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchStoreData(silent: true);
    }
  }

  Future<void> _fetchStoreData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoadingStore = true);
    }
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/sellers/${_seller.id}'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        if (body['success'] == true && body['data'] is Map) {
          final payload = Map<String, dynamic>.from(body['data'] as Map);
          final List<dynamic> rawProducts = payload['products'] is List
              ? List<dynamic>.from(payload['products'] as List)
              : <dynamic>[];
          final List<dynamic> rawMainCats =
              payload['store_main_categories'] is List
                  ? List<dynamic>.from(payload['store_main_categories'] as List)
                  : <dynamic>[];
          final List<dynamic> rawSubCats = payload['subcategories'] is List
              ? List<dynamic>.from(payload['subcategories'] as List)
              : <dynamic>[];
          final List<dynamic> rawVouchers = payload['store_vouchers'] is List
              ? List<dynamic>.from(payload['store_vouchers'] as List)
              : <dynamic>[];

          setState(() {
            if (payload['seller'] is Map) {
              _seller = SellerProfile.fromJson(
                  Map<String, dynamic>.from(payload['seller'] as Map));
            }
            if (payload['stats'] is Map) {
              _stats = Map<String, dynamic>.from(payload['stats'] as Map);
            }
            _isFollowing = payload['is_following'] == true;
            _isOwnStore = payload['is_own_store'] == true;
            _mainCategories = rawMainCats.map((e) => e.toString()).toList();
            _subCategories = rawSubCats.map((e) => e.toString()).toList();
            _storeVouchers = [
              for (final v in rawVouchers)
                if (v is Map) Map<String, dynamic>.from(v),
            ];
            _allProducts = [
              for (final p in rawProducts)
                if (p is Map) Product.fromJson(Map<String, dynamic>.from(p)),
            ];
            _isLoadingStore = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoadingStore = false);
    }
  }

  Future<void> _openReportSellerModal() async {
    List<JsonMap> reasons = [
      {'key': 'counterfeit', 'label': 'Counterfeit / Fake Goods'},
      {'key': 'scam_fraud', 'label': 'Suspected Scam or Off-Platform Payment'},
      {'key': 'abusive_chat', 'label': 'Abusive or Harassing Behavior'},
      {'key': 'prohibited_items', 'label': 'Prohibited or Illegal Listings'},
      {'key': 'other', 'label': 'Other Marketplace Violation'},
    ];
    List<JsonMap> eligibleOrders = [];

    try {
      final ctxRes = await http.get(
        Uri.parse('$_domain/api/v1/sellers/${_seller.id}/report/context'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (ctxRes.statusCode == 200) {
        final body = json.decode(ctxRes.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          if (d['has_open_report'] == true) {
            _showSnack(
              'You already have an open report against this store under Admin review.',
              true,
            );
            return;
          }
          if (d['reasons'] is List && (d['reasons'] as List).isNotEmpty) {
            final List<dynamic> rawReasons =
                List<dynamic>.from(d['reasons'] as List);
            reasons = rawReasons.map<JsonMap>((r) {
              if (r is Map) {
                return {
                  'key': (r['key'] ?? r['value'] ?? 'other').toString(),
                  'label': (r['label'] ?? r['title'] ?? 'Other').toString(),
                };
              }
              return {'key': r.toString(), 'label': r.toString()};
            }).toList();
          }
          if (d['orders'] is List) {
            final List<dynamic> rawOrders =
                List<dynamic>.from(d['orders'] as List);
            eligibleOrders = [
              for (final o in rawOrders)
                if (o is Map) Map<String, dynamic>.from(o),
            ];
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;

    String selectedReasonKey = reasons.first['key']!.toString();
    int? selectedOrderId;
    final descCtrl = TextEditingController();
    List<XFile> evidencePhotos = [];
    String? modalError;
    bool isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 18,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Report ${_seller.businessName}',
                            style: const TextStyle(
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
                    DropdownButtonFormField<String>(
                      initialValue: selectedReasonKey,
                      decoration: const InputDecoration(
                        labelText: 'Violation Category *',
                      ),
                      items: reasons
                          .map((r) => DropdownMenuItem<String>(
                                value: r['key']!.toString(),
                                child: Text(
                                  r['label']!.toString(),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => selectedReasonKey = val);
                        }
                      },
                    ),
                    if (eligibleOrders.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int?>(
                        initialValue: selectedOrderId,
                        decoration: const InputDecoration(
                          labelText: 'Related Store Order (Optional)',
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('None / General Store Report'),
                          ),
                          ...eligibleOrders.map((o) {
                            final int oid =
                                int.tryParse(o['id']?.toString() ?? '0') ?? 0;
                            final String ono =
                                o['seller_order_number']?.toString() ?? '#$oid';
                            return DropdownMenuItem<int?>(
                              value: oid,
                              child: Text('Order $ono'),
                            );
                          }),
                        ],
                        onChanged: (val) =>
                            setModalState(() => selectedOrderId = val),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Describe the Violation (15+ chars) *',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked =
                            await picker.pickMultiImage(imageQuality: 85);
                        if (picked.isNotEmpty) {
                          setModalState(() {
                            evidencePhotos = picked.take(5).toList();
                          });
                        }
                      },
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: Text(
                        evidencePhotos.isEmpty
                            ? 'Attach Evidence Photos (Optional, Max 5)'
                            : '${evidencePhotos.length} photo(s) attached',
                      ),
                    ),
                    if (evidencePhotos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: evidencePhotos
                            .map((f) => ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(f.path),
                                    width: 48,
                                    height: 48,
                                    fit: BoxFit.cover,
                                  ),
                                ))
                            .toList(),
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
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: StorkTheme.danger,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                final text = descCtrl.text.trim();
                                if (text.length < 15) {
                                  setModalState(() {
                                    modalError =
                                        'Please provide at least 15 characters describing the issue.';
                                  });
                                  return;
                                }
                                setModalState(() {
                                  isSubmitting = true;
                                  modalError = null;
                                });
                                try {
                                  final req = http.MultipartRequest(
                                    'POST',
                                    Uri.parse(
                                        '$_domain/api/v1/sellers/${_seller.id}/report'),
                                  );
                                  req.headers['Authorization'] =
                                      'Bearer ${widget.token}';
                                  req.headers['Accept'] = 'application/json';
                                  req.fields['reason_category'] =
                                      selectedReasonKey;
                                  req.fields['description'] = text;
                                  if (selectedOrderId != null) {
                                    req.fields['seller_order_id'] =
                                        '$selectedOrderId';
                                  }
                                  for (final f in evidencePhotos) {
                                    req.files.add(
                                      await http.MultipartFile.fromPath(
                                        'evidence_photos[]',
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

                                  if ((res.statusCode == 200 ||
                                          res.statusCode == 201) &&
                                      data is Map &&
                                      data['success'] == true) {
                                    if (modalContext.mounted) {
                                      Navigator.pop(modalContext);
                                    }
                                    _showSnack(
                                      data['message']?.toString() ??
                                          'Store report submitted to Storkia Admin.',
                                      false,
                                    );
                                  } else {
                                    setModalState(() {
                                      modalError = data is Map
                                          ? (data['message']?.toString() ??
                                              'Failed to submit report.')
                                          : 'Failed to submit report.';
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
                            : const Text('Submit Report to Admin'),
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

  Future<void> _toggleFollow() async {
    if (_isTogglingFollow || _isOwnStore) return;
    setState(() => _isTogglingFollow = true);

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/sellers/${_seller.id}/follow'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        setState(() {
          _isFollowing = data['is_following'] == true;
          _stats['followers'] = data['followers_count'] ?? _stats['followers'];
        });
        _showSnack(
            data['message']?.toString() ?? 'Updated follow status.', false);
      } else {
        _showSnack(
            data['message']?.toString() ?? 'Unable to follow store.', true);
      }
    } catch (_) {
      _showSnack('Network error occurred.', true);
    } finally {
      if (mounted) setState(() => _isTogglingFollow = false);
    }
  }

  Future<void> _claimStoreVoucher(String code) async {
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
              'seller_profile_id': _seller.id,
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
        _showSnack(
            data['message']?.toString() ?? 'Voucher claimed to wallet!', false);
      } else {
        _showSnack(
            data['message']?.toString() ?? 'Failed to claim voucher.', true);
      }
    } catch (_) {
      _showSnack('Network error occurred.', true);
    }
  }

  Future<void> _chatWithSeller() async {
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
          contactId: _seller.userId,
        );

        if (!mounted) return;
        Navigator.pop(context);

        if (contactRes['success'] == true) {
          final List<ChatContact> contacts =
              List<ChatContact>.from(contactRes['data'] as List);
          if (contacts.isNotEmpty) {
            final contact = contacts.firstWhere(
              (c) => c.id == _seller.userId,
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
      _showSnack('Unable to open chat right now.', true);
    } catch (_) {
      if (mounted) Navigator.pop(context);
      _showSnack('Network error occurred.', true);
    }
  }

  List<Product> get _filteredProducts {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allProducts.where((p) {
      final matchSearch = q.isEmpty || p.name.toLowerCase().contains(q);
      final matchMain = _selectedMainCategory.isEmpty ||
          (p.category ?? _seller.lineOfBusiness) == _selectedMainCategory;
      final matchSub = _selectedSubCategory.isEmpty ||
          (p.subcategory ?? '') == _selectedSubCategory;
      return matchSearch && matchMain && matchSub;
    }).toList();

    switch (_sortBy) {
      case 'price_asc':
        filtered.sort((a, b) => a.discountedPrice.compareTo(b.discountedPrice));
        break;
      case 'price_desc':
        filtered.sort((a, b) => b.discountedPrice.compareTo(a.discountedPrice));
        break;
      case 'az':
        filtered.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case 'za':
        filtered.sort(
            (a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case 'oldest':
        filtered.sort((a, b) => a.id.compareTo(b.id));
        break;
      case 'newest':
      default:
        filtered.sort((a, b) => b.id.compareTo(a.id));
        break;
    }
    return filtered;
  }

  void _showSnack(String message, bool isError) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? StorkTheme.danger : StorkTheme.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = _seller.logoPath != null
        ? ApiConfig.storageUrl(_seller.logoPath, _domain)
        : '';
    final filteredList = _filteredProducts;
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 700 ? 3 : 2;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(_seller.businessName),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Store Products',
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'newest', child: Text('Newest Added')),
              PopupMenuItem(value: 'oldest', child: Text('Oldest Added')),
              PopupMenuItem(
                  value: 'price_asc', child: Text('Price: Low to High')),
              PopupMenuItem(
                  value: 'price_desc', child: Text('Price: High to Low')),
              PopupMenuItem(value: 'az', child: Text('Name: A to Z')),
              PopupMenuItem(value: 'za', child: Text('Name: Z to A')),
            ],
          ),
          if (!_isOwnStore)
            IconButton(
              onPressed: _openReportSellerModal,
              tooltip: 'Report Store',
              icon: const Icon(
                Icons.flag_outlined,
                color: StorkTheme.danger,
              ),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  color: StorkTheme.surface,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor:
                                StorkTheme.primary.withValues(alpha: 0.12),
                            backgroundImage: logoUrl.isNotEmpty
                                ? NetworkImage(logoUrl)
                                : null,
                            child: logoUrl.isEmpty
                                ? Text(
                                    _seller.businessName.isNotEmpty
                                        ? _seller.businessName[0].toUpperCase()
                                        : 'S',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: StorkTheme.primary,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _seller.businessName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _mainCategories.isNotEmpty
                                      ? _mainCategories.join(' • ')
                                      : _seller.lineOfBusiness,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_seller.municipality}, ${_seller.province}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (!_isOwnStore)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    _isTogglingFollow ? null : _toggleFollow,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isFollowing
                                      ? StorkTheme.surfaceSubtle
                                      : StorkTheme.primary,
                                  foregroundColor: _isFollowing
                                      ? StorkTheme.textMain
                                      : Colors.white,
                                ),
                                child: Text(
                                  _isFollowing
                                      ? '✓ Following Store'
                                      : '+ Follow Store (Get ₱30 Voucher)',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: _chatWithSeller,
                              icon: const Icon(
                                  Icons.chat_bubble_outline_rounded,
                                  size: 17),
                              label: const Text('Chat Now'),
                            ),
                          ],
                        ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: StorkTheme.surfaceSubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildStatColumn('Chat Rate',
                                '${_stats['chat_response_rate'] ?? 98}%'),
                            _buildStatColumn(
                                'Followers', '${_stats['followers'] ?? 0}'),
                            _buildStatColumn('Rating',
                                '${_stats['ratings'] ?? '0.0'} / 5.0'),
                            _buildStatColumn('Products',
                                '${_stats['products_count'] ?? _allProducts.length}'),
                          ],
                        ),
                      ),
                      if (_storeVouchers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'EXCLUSIVE STORE VOUCHERS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 68,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _storeVouchers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) {
                              final sv = _storeVouchers[index];
                              final code = sv['code']?.toString() ?? '';
                              final badge =
                                  sv['badge_label']?.toString() ?? 'OFF';
                              final minSpend = double.tryParse(
                                      sv['min_spend']?.toString() ?? '0') ??
                                  0;
                              final claimed = sv['is_claimed'] == true;

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: StorkTheme.brandLight
                                      .withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: StorkTheme.primary
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          '$code • $badge',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: StorkTheme.primaryDark,
                                          ),
                                        ),
                                        Text(
                                          'Min. ₱${minSpend.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: StorkTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    ElevatedButton(
                                      onPressed: claimed
                                          ? null
                                          : () => _claimStoreVoucher(code),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        minimumSize: const Size(0, 32),
                                      ),
                                      child: Text(
                                        claimed ? 'Claimed' : 'Claim',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  color: StorkTheme.surface,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Search products in this store...',
                          prefixIcon: Icon(Icons.search_rounded, size: 19),
                        ),
                      ),
                      if (_mainCategories.length > 1 ||
                          _subCategories.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _buildCategoryChip(
                                label: 'All Items',
                                isSelected: _selectedMainCategory.isEmpty &&
                                    _selectedSubCategory.isEmpty,
                                onTap: () => setState(() {
                                  _selectedMainCategory = '';
                                  _selectedSubCategory = '';
                                }),
                              ),
                              for (final mCat in _mainCategories)
                                _buildCategoryChip(
                                  label: mCat,
                                  isSelected: _selectedMainCategory == mCat &&
                                      _selectedSubCategory.isEmpty,
                                  onTap: () => setState(() {
                                    _selectedMainCategory = mCat;
                                    _selectedSubCategory = '';
                                  }),
                                ),
                              for (final sCat in _subCategories)
                                _buildCategoryChip(
                                  label: sCat,
                                  isSelected: _selectedSubCategory == sCat,
                                  onTap: () => setState(() {
                                    _selectedSubCategory = sCat;
                                  }),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          _isLoadingStore
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child:
                          CircularProgressIndicator(color: StorkTheme.primary),
                    ),
                  ),
                )
              : filteredList.isEmpty
                  ? const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: Text(
                            'No store products match your filter.',
                            style: TextStyle(color: StorkTheme.textMuted),
                          ),
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return ProductCard(
                              product: filteredList[index],
                              baseUrl: _domain,
                              token: widget.token,
                            );
                          },
                          childCount: filteredList.length,
                        ),
                      ),
                    ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
        ],
      ),
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: StorkTheme.primaryDark,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: StorkTheme.textMuted),
        ),
      ],
    );
  }

  Widget _buildCategoryChip({
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
          color: isSelected ? StorkTheme.primary : StorkTheme.surfaceSubtle,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? StorkTheme.primary : StorkTheme.borderSubtle,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : StorkTheme.textMain,
          ),
        ),
      ),
    );
  }
}
