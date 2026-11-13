import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../config/app_routes.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../providers/wishlist_provider.dart';
import '../screens/product_show.dart';

class ProductCard extends ConsumerWidget {
  final Product product;
  final String baseUrl;
  final String token;

  const ProductCard({
    super.key,
    required this.product,
    required this.baseUrl,
    required this.token,
  });

  String _formatMoney(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wishlistState = ref.watch(wishlistProvider);
    final isFavorite =
        wishlistState.productIds.contains(product.id) || product.isWishlisted;

    final imageUrl = product.pictures.isNotEmpty
        ? ApiConfig.storageUrl(product.pictures.first, baseUrl)
        : '';
    final storeName = product.sellerProfile?.businessName ?? '';
    final isVacation = product.isStoreOnVacation;
    final isSoldOut = product.stockQuantity <= 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          StorkRoute.fade(
            ProductShowScreen(
              product: product,
              baseUrl: baseUrl,
              token: token,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: StorkTheme.borderSubtle),
          boxShadow: StorkTheme.softCardShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: StorkTheme.surfaceSubtle,
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Center(
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                color: StorkTheme.textMuted,
                                size: 30,
                              ),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 36,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                  ),
                  if (product.discount > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [StorkTheme.danger, StorkTheme.primary],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '-${product.discount.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  if (isSoldOut || isVacation)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSoldOut
                              ? Colors.black.withValues(alpha: 0.78)
                              : StorkTheme.warning,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSoldOut ? 'SOLD OUT' : 'ON VACATION',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  if (token.isNotEmpty)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.hardEdge,
                        child: InkWell(
                          onTap: () {
                            ref
                                .read(wishlistProvider.notifier)
                                .toggleWishlist(baseUrl, token, product);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 17,
                              color: isFavorite
                                  ? StorkTheme.danger
                                  : StorkTheme.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (storeName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.storefront_rounded,
                            size: 11,
                            color: StorkTheme.textMuted,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              storeName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: StorkTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: StorkTheme.textMain,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          '₱${_formatMoney(product.discountedPrice)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: product.discount > 0
                                ? StorkTheme.price
                                : StorkTheme.primary,
                          ),
                        ),
                      ),
                      if (product.discount > 0) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '₱${_formatMoney(product.price)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              decoration: TextDecoration.lineThrough,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (product.avgRating > 0) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 12.5,
                          color: Colors.amber,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          product.avgRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMain,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          product.soldCount > 0
                              ? '${product.soldCount} sold'
                              : (product.category ?? 'In Stock'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: StorkTheme.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
