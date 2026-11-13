import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';

typedef JsonMap = Map<String, dynamic>;
typedef IntIntMap = Map<int, int>;
typedef IntControllerMap = Map<int, TextEditingController>;
typedef XFileList = List<XFile>;
typedef IntPhotosMap = Map<int, XFileList>;
typedef StringIntMap = Map<String, int>;
typedef StringMap = Map<String, String>;

class LeaveReviewScreen extends ConsumerStatefulWidget {
  final JsonMap sellerOrder;
  final String baseUrl;
  final String token;

  const LeaveReviewScreen({
    super.key,
    required this.sellerOrder,
    required this.baseUrl,
    required this.token,
  });

  @override
  ConsumerState<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends ConsumerState<LeaveReviewScreen> {
  final IntIntMap _itemRatings = {};
  final IntControllerMap _itemCommentControllers = {};
  final IntPhotosMap _itemPhotos = {};

  int _parcelConditionRating = 5;
  int _sellerServiceRating = 5;
  int _logisticsHubRating = 5;
  int _riderDeliveryRating = 5;
  final TextEditingController _overallCommentController =
      TextEditingController();

  bool _isSubmitting = false;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  static const List<String> _productQuickTags = [
    'Matches description & photos',
    'Excellent build quality',
    'Great value for price',
    'Authentic & fresh item',
  ];

  @override
  void initState() {
    super.initState();
    final List<dynamic> items = widget.sellerOrder['items'] is List
        ? List<dynamic>.from(widget.sellerOrder['items'] as List)
        : <dynamic>[];
    for (final rawItem in items) {
      if (rawItem is Map) {
        final int itemId = int.tryParse(rawItem['id']?.toString() ?? '0') ?? 0;
        if (itemId > 0) {
          _itemRatings[itemId] = 5;
          _itemCommentControllers[itemId] = TextEditingController();
          _itemPhotos[itemId] = <XFile>[];
        }
      }
    }
  }

  @override
  void dispose() {
    for (final ctrl in _itemCommentControllers.values) {
      ctrl.dispose();
    }
    _overallCommentController.dispose();
    super.dispose();
  }

  void _appendTag(int? itemId, String tagText) {
    if (itemId != null && _itemCommentControllers.containsKey(itemId)) {
      final ctrl = _itemCommentControllers[itemId]!;
      final current = ctrl.text.trim();
      ctrl.text = current.isEmpty ? tagText : '$current • $tagText';
    } else {
      final current = _overallCommentController.text.trim();
      _overallCommentController.text =
          current.isEmpty ? tagText : '$current • $tagText';
    }
    setState(() {});
  }

  Future<void> _pickItemPhotos(int itemId) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(
      imageQuality: 82,
    );
    if (picked.isEmpty) return;

    final existing = XFileList.from(_itemPhotos[itemId] ?? <XFile>[]);
    for (final file in picked) {
      if (existing.length >= 5) {
        _showError('Maximum of 5 review photos allowed per item.');
        break;
      }
      final len = await file.length();
      if (len > 5 * 1024 * 1024) {
        _showError('Each product photo must not exceed 5MB.');
        continue;
      }
      existing.add(file);
    }
    setState(() => _itemPhotos[itemId] = existing);
  }

  Future<void> _submitRatings() async {
    setState(() => _isSubmitting = true);

    try {
      final orderId = widget.sellerOrder['id'];
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_domain/api/v1/orders/$orderId/reviews'),
      );
      req.headers['Authorization'] = 'Bearer ${widget.token}';
      req.headers['Accept'] = 'application/json';

      final StringIntMap ratingsPayload = {};
      final StringMap reviewsPayload = {};

      _itemRatings.forEach((itemId, stars) {
        ratingsPayload[itemId.toString()] = stars;
      });
      _itemCommentControllers.forEach((itemId, ctrl) {
        reviewsPayload[itemId.toString()] = ctrl.text.trim();
      });

      req.fields['item_ratings'] = json.encode(ratingsPayload);
      req.fields['item_reviews'] = json.encode(reviewsPayload);
      req.fields['parcel_condition_rating'] = '$_parcelConditionRating';
      req.fields['seller_service_rating'] = '$_sellerServiceRating';
      req.fields['logistics_hub_rating'] = '$_logisticsHubRating';
      req.fields['rider_delivery_rating'] = '$_riderDeliveryRating';
      req.fields['review_comment'] = _overallCommentController.text.trim();

      for (final entry in _itemPhotos.entries) {
        final files = entry.value;
        if (files.isNotEmpty) {
          req.files.add(
            await http.MultipartFile.fromPath(
              'item_photo_${entry.key}',
              files.first.path,
            ),
          );
          for (final f in files) {
            req.files.add(
              await http.MultipartFile.fromPath(
                'item_photos_${entry.key}[]',
                f.path,
              ),
            );
          }
        }
      }

      final streamed = await req.send().timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;
      final data = json.decode(response.body);

      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data is Map &&
          data['success'] == true) {
        await syncAllBuyerCounters(ref, widget.token);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ??
                  'Thank you! Your 5-point rating has been submitted.',
            ),
            backgroundColor: StorkTheme.success,
          ),
        );
        Navigator.pop(context, true);
      } else {
        String err = data is Map
            ? (data['message']?.toString() ?? 'Failed to submit ratings.')
            : 'Failed to submit ratings.';
        if (data is Map &&
            data['errors'] is Map &&
            (data['errors'] as Map).isNotEmpty) {
          final first = (data['errors'] as Map).values.first;
          if (first is List && first.isNotEmpty) {
            err = first.first.toString();
          }
        }
        _showError(err);
      }
    } catch (_) {
      _showError('Network error occurred while submitting ratings.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: StorkTheme.danger,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sellerName =
        widget.sellerOrder['seller_profile']?['business_name']?.toString() ??
            'Seller Store';
    final logisticsName =
        widget.sellerOrder['logistics_profile']?['business_name']?.toString() ??
            'Logistics Sorting Hub';
    final riderName = widget.sellerOrder['shipment']?['current_rider']
                ?['first_name'] !=
            null
        ? '${widget.sellerOrder['shipment']['current_rider']['first_name']} ${widget.sellerOrder['shipment']['current_rider']['last_name'] ?? ''}'
            .trim()
        : 'Assigned Last-Mile Rider';
    final List<dynamic> items = widget.sellerOrder['items'] is List
        ? List<dynamic>.from(widget.sellerOrder['items'] as List)
        : <dynamic>[];

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(
          'Rate Order #${widget.sellerOrder['seller_order_number'] ?? ''}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: StorkTheme.brandGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: StorkTheme.primaryDark.withValues(alpha: 0.16),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'EARN UP TO +10 STORKIA COINS PER ITEM',
                    style: TextStyle(
                      color: StorkTheme.brandLight,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Who & What Are You Rating?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rate (1) Product Quality (+5 Coins for text review or +10 Coins with photo), (2) Parcel Condition, (3) $sellerName Store Service, (4) $logisticsName Hub, and (5) $riderName to unlock Buy Again.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
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
                  '1. PRODUCT QUALITY RATING',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    color: StorkTheme.primary,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rate Purchased Product(s) from $sellerName',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const Divider(height: 22),
                for (int i = 0; i < items.length; i++)
                  if (items[i] is Map) ...[
                    if (i > 0) const Divider(height: 24),
                    _buildProductRatingBlock(JsonMap.from(items[i] as Map)),
                  ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildServiceDimensionCard(
            stepLabel: '2. PARCEL & PACKAGING CONDITION',
            title: 'Outer box, bubble wrap & seal integrity',
            subtitle:
                'Did the parcel arrive sealed, dry, and undamaged without dents?',
            rating: _parcelConditionRating,
            onRatingChanged: (v) => setState(() => _parcelConditionRating = v),
            quickTags: const [
              'Well-packed with bubble wrap',
              'Tamper-proof seal intact',
              'Zero dents on box',
            ],
          ),
          const SizedBox(height: 14),
          _buildServiceDimensionCard(
            stepLabel: '3. SELLER STORE SERVICE',
            title: 'Store: $sellerName',
            subtitle:
                'Order preparation speed, chat responsiveness, and following your buyer note.',
            rating: _sellerServiceRating,
            onRatingChanged: (v) => setState(() => _sellerServiceRating = v),
            quickTags: const [
              'Fast seller acceptance',
              'Accommodating & polite seller',
              'Followed buyer note accurately',
            ],
          ),
          const SizedBox(height: 14),
          _buildServiceDimensionCard(
            stepLabel: '4. LOGISTICS SORTING HUB',
            title: 'Hub: $logisticsName',
            subtitle:
                'First-mile pickup coordination, sorting hub turnaround time, and accurate tracking updates.',
            rating: _logisticsHubRating,
            onRatingChanged: (v) => setState(() => _logisticsHubRating = v),
            quickTags: const [
              'Fast hub sorting & dispatch',
              'Real-time QR tracking logs',
              'Safe parcel handling at hub',
            ],
          ),
          const SizedBox(height: 14),
          _buildServiceDimensionCard(
            stepLabel: '5. LAST-MILE DELIVERY RIDER',
            title: 'Rider: $riderName',
            subtitle:
                'Doorstep courtesy, calling/texting upon arrival, and proper photo proof of delivery.',
            rating: _riderDeliveryRating,
            onRatingChanged: (v) => setState(() => _riderDeliveryRating = v),
            quickTags: const [
              'Polite & courteous rider',
              'Called before doorstep arrival',
              'Handled parcel with care',
            ],
          ),
          const SizedBox(height: 14),
          Container(
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
                  'OVERALL ORDER & DELIVERY EXPERIENCE SUMMARY (OPTIONAL)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _overallCommentController,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: const InputDecoration(
                    hintText:
                        'Share your overall experience with the store, packaging, logistics hub, and rider...',
                    fillColor: StorkTheme.surfaceSubtle,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: _isSubmitting ? null : StorkTheme.brandGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRatings,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Submit Ratings & Unlock Buy Again'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildProductRatingBlock(JsonMap item) {
    final int itemId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
    final int currentStars = _itemRatings[itemId] ?? 5;
    final XFileList photos = _itemPhotos[itemId] ?? <XFile>[];
    final bool hasText =
        (_itemCommentControllers[itemId]?.text.trim().isNotEmpty ?? false);
    final int bonusCoins = photos.isNotEmpty ? 10 : (hasText ? 5 : 0);
    final String imgUrl = item['product_image'] != null
        ? ApiConfig.storageUrl(item['product_image'].toString(), _domain)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: imgUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.network(imgUrl, fit: BoxFit.cover),
                    )
                  : const Icon(
                      Icons.inventory_2_outlined,
                      color: StorkTheme.textMuted,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['product_name']?.toString() ?? 'Product',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                    ),
                  ),
                  if (item['variant_name'] != null)
                    Text(
                      [item['variant_name'], item['sub_variant_name']]
                          .where((e) => e != null && e.toString().isNotEmpty)
                          .join(' / '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: bonusCoins > 0
                    ? StorkTheme.success.withValues(alpha: 0.12)
                    : StorkTheme.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                bonusCoins > 0 ? '+$bonusCoins Coins Ready' : '+Up to 10 Coins',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: bonusCoins > 0
                      ? StorkTheme.success
                      : const Color(0xFF92400E),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (int star = 1; star <= 5; star++)
              GestureDetector(
                onTap: () => setState(() => _itemRatings[itemId] = star),
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    star <= currentStars
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 30,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              '$currentStars/5',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: StorkTheme.primaryDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final chip in _productQuickTags)
              InkWell(
                onTap: () => _appendTag(itemId, chip),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: StorkTheme.surfaceSubtle,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: StorkTheme.borderSubtle),
                  ),
                  child: Text(
                    '+ $chip',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: StorkTheme.textMain,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _itemCommentControllers[itemId],
          maxLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText:
                'Write your product review (+5 Coins, or +10 Coins with photo)...',
            fillColor: StorkTheme.surfaceSubtle,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed:
                  photos.length >= 5 ? null : () => _pickItemPhotos(itemId),
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: Text(
                photos.isEmpty
                    ? 'Add Product Photos (+10 Coins)'
                    : 'Photos (${photos.length}/5)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            for (int pIdx = 0; pIdx < photos.length; pIdx++)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photos[pIdx].path),
                      width: 46,
                      height: 46,
                      fit: BoxFit.cover,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _itemPhotos[itemId]?.removeAt(pIdx);
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
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildServiceDimensionCard({
    required String stepLabel,
    required String title,
    required String subtitle,
    required int rating,
    required ValueChanged<int> onRatingChanged,
    required List<String> quickTags,
  }) {
    return Container(
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
          Text(
            stepLabel,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              color: StorkTheme.primary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11.5,
              color: StorkTheme.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (int star = 1; star <= 5; star++)
                GestureDetector(
                  onTap: () => onRatingChanged(star),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      star <= rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: Colors.amber,
                      size: 28,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                '$rating/5',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: StorkTheme.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in quickTags)
                InkWell(
                  onTap: () => _appendTag(null, tag),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: StorkTheme.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: Text(
                      '+ $tag',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: StorkTheme.textMain,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
