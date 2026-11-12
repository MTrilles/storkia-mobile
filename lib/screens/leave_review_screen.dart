import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';

class LeaveReviewScreen extends StatefulWidget {
  final Map<String, dynamic> sellerOrder;
  final String baseUrl;
  final String token;

  const LeaveReviewScreen({
    super.key,
    required this.sellerOrder,
    required this.baseUrl,
    required this.token,
  });

  @override
  State<LeaveReviewScreen> createState() => _LeaveReviewScreenState();
}

class _LeaveReviewScreenState extends State<LeaveReviewScreen> {
  final Map<int, int> _itemRatings = {};
  final Map<int, TextEditingController> _itemCommentControllers = {};
  final Map<int, XFile?> _itemPhotos = {};

  int _parcelConditionRating = 5;
  int _sellerServiceRating = 5;
  int _logisticsHubRating = 5;
  int _riderDeliveryRating = 5;
  final TextEditingController _overallCommentController =
      TextEditingController();

  bool _isSubmitting = false;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    final List items = widget.sellerOrder['items'] as List? ?? [];
    for (final rawItem in items) {
      if (rawItem is Map) {
        final int itemId = int.tryParse(rawItem['id']?.toString() ?? '0') ?? 0;
        if (itemId > 0) {
          _itemRatings[itemId] = 5;
          _itemCommentControllers[itemId] = TextEditingController();
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

  Future<void> _pickItemPhoto(int itemId) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
    if (file != null) {
      final len = await file.length();
      if (len > 5 * 1024 * 1024) {
        _showError('Product photo must not exceed 5MB.');
        return;
      }
      setState(() => _itemPhotos[itemId] = file);
    }
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

      final Map<String, int> ratingsPayload = {};
      final Map<String, String> reviewsPayload = {};

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
        if (entry.value != null) {
          req.files.add(
            await http.MultipartFile.fromPath(
              'item_photo_${entry.key}',
              entry.value!.path,
            ),
          );
        }
      }

      final streamed = await req.send().timeout(ApiConfig.requestTimeout);
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
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
        _showError(data['message']?.toString() ?? 'Failed to submit ratings.');
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
    final List items = widget.sellerOrder['items'] as List? ?? [];

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(
            'Rate Order #${widget.sellerOrder['seller_order_number'] ?? ''}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [StorkTheme.primaryDark, StorkTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'COMPLETE ORDER FEEDBACK GUIDE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Who & What Are You Rating?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Rate (1) Product Quality, (2) Parcel Condition, (3) $sellerName Store Service, (4) $logisticsName Hub, and (5) $riderName to unlock Buy Again.',
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
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1. PRODUCT QUALITY RATING',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rate Purchased Product(s) from $sellerName',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMain,
                  ),
                ),
                const Divider(height: 22),
                for (int i = 0; i < items.length; i++)
                  if (items[i] is Map) ...[
                    if (i > 0) const Divider(height: 24),
                    _buildProductRatingBlock(
                        Map<String, dynamic>.from(items[i])),
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
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OVERALL ORDER & DELIVERY EXPERIENCE SUMMARY (OPTIONAL)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.textMuted,
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
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submitRatings,
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

  Widget _buildProductRatingBlock(Map<String, dynamic> item) {
    final int itemId = int.tryParse(item['id']?.toString() ?? '0') ?? 0;
    final int currentStars = _itemRatings[itemId] ?? 5;
    final XFile? photo = _itemPhotos[itemId];
    final String imgUrl = item['product_image'] != null
        ? ApiConfig.storageUrl(item['product_image'].toString(), _domain)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: imgUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Image.network(imgUrl, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.inventory_2_outlined,
                      color: StorkTheme.textMuted),
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
          ],
        ),
        const SizedBox(height: 10),
        Row(
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
            'Matches description & photos',
            'Excellent build quality',
            'Great value for price',
            'Authentic & fresh item',
          ].map((chip) {
            return InkWell(
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
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _itemCommentControllers[itemId],
          maxLines: 2,
          decoration: InputDecoration(
            hintText:
                'Write your product review for ${item['product_name'] ?? 'this item'}...',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickItemPhoto(itemId),
              icon: const Icon(Icons.add_a_photo_outlined, size: 16),
              label: Text(
                photo != null ? 'Photo Attached' : 'Add Product Photo (WebP)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (photo != null) ...[
              const SizedBox(width: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(photo.path),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() => _itemPhotos[itemId] = null),
              ),
            ],
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepLabel,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: StorkTheme.textMain,
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
          Row(
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
            children: quickTags.map((tag) {
              return InkWell(
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
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
