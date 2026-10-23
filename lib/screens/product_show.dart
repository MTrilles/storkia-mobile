import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../components/product_card.dart';
import '../services/api_service.dart';

class ProductShowScreen extends StatefulWidget {
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
  State<ProductShowScreen> createState() => _ProductShowScreenState();
}

class _ProductShowScreenState extends State<ProductShowScreen> {
  final ScrollController _scrollController = ScrollController();

  int? _selectedMainIndex;
  int? _selectedSubIndex;

  late String _currentImage;
  late double _activePrice;
  late int _activeStock;
  int _quantity = 1;

  late bool _hasVariants;
  bool _hasSubVariants = false;
  late int _totalStock;

  // Suggestions state
  List<Product> _suggestedProducts = [];
  bool _isLoadingSuggestions = true;
  bool _isFetchingMoreSuggestions = false;
  int _currentSuggestionPage = 1;
  bool _hasMoreSuggestions = true;

  @override
  void initState() {
    super.initState();
    _currentImage = widget.product.pictures.isNotEmpty
        ? '${widget.baseUrl}/storage/${widget.product.pictures[0]}'
        : '';
    _activePrice = widget.product.price;

    _hasVariants = widget.product.variants != null &&
        widget.product.variants!['items'] != null &&
        (widget.product.variants!['items'] as List).isNotEmpty;

    _totalStock = _calculateTotalStock();
    _activeStock = _totalStock;

    _fetchSuggestions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isFetchingMoreSuggestions && _hasMoreSuggestions) {
        _fetchSuggestions(loadMore: true);
      }
    }
  }

  Future<void> _fetchSuggestions({bool loadMore = false}) async {
    if (loadMore) {
      setState(() => _isFetchingMoreSuggestions = true);
    } else {
      setState(() => _isLoadingSuggestions = true);
    }

    final result = await ApiService.getProducts(widget.token,
        page: _currentSuggestionPage);

    if (result['success']) {
      final Map<String, dynamic> paginatedData =
          result['data']['data'] ?? result['data'];
      final List<dynamic> productsJson = paginatedData['data'] ?? [];
      final int lastPage = paginatedData['last_page'] ?? 1;

      final List<Product> newProducts = productsJson
          .map((json) => Product.fromJson(json))
          .where((p) => p.id != widget.product.id) // Exclude current product
          .toList();

      setState(() {
        if (loadMore) {
          _suggestedProducts.addAll(newProducts);
        } else {
          _suggestedProducts = newProducts;
        }

        if (_currentSuggestionPage >= lastPage) {
          _hasMoreSuggestions = false;
        } else {
          _currentSuggestionPage++;
        }

        _isLoadingSuggestions = false;
        _isFetchingMoreSuggestions = false;
      });
    } else {
      setState(() {
        _isLoadingSuggestions = false;
        _isFetchingMoreSuggestions = false;
      });
    }
  }

  int _calculateTotalStock() {
    int total = 0;
    if (_hasVariants) {
      List items = widget.product.variants!['items'];
      for (var item in items) {
        if (item['subs'] != null && (item['subs'] as List).isNotEmpty) {
          for (var sub in item['subs']) {
            total += int.tryParse(sub['stock'].toString()) ?? 0;
          }
        } else {
          total += int.tryParse(item['stock'].toString()) ?? 0;
        }
      }
    } else {
      total = widget.product.stockQuantity;
    }
    return total;
  }

  double get _discountedActivePrice {
    if (widget.product.discount > 0) {
      return _activePrice - (_activePrice * (widget.product.discount / 100));
    }
    return _activePrice;
  }

  void _onMainVariantSelected(int index, Map<String, dynamic> item) {
    setState(() {
      if (_selectedMainIndex == index) {
        _selectedMainIndex = null;
        _selectedSubIndex = null;
        _hasSubVariants = false;
        _activePrice = widget.product.price;
        _activeStock = _totalStock;
        _currentImage = widget.product.pictures.isNotEmpty
            ? '${widget.baseUrl}/storage/${widget.product.pictures[0]}'
            : '';
      } else {
        _selectedMainIndex = index;
        _selectedSubIndex = null;

        _hasSubVariants =
            item['subs'] != null && (item['subs'] as List).isNotEmpty;

        if (item['price'] != null) {
          _activePrice =
              double.tryParse(item['price'].toString()) ?? widget.product.price;
        }

        if (_hasSubVariants) {
          int parentStock = 0;
          for (var sub in item['subs']) {
            parentStock += int.tryParse(sub['stock'].toString()) ?? 0;
          }
          _activeStock = parentStock;
        } else {
          _activeStock = int.tryParse(item['stock'].toString()) ?? 0;
        }

        if (item['image'] != null && item['image'].toString().isNotEmpty) {
          _currentImage = '${widget.baseUrl}/storage/${item['image']}';
        }
      }
      _quantity = 1;
    });
  }

  void _onSubVariantSelected(
      int index, Map<String, dynamic> sub, Map<String, dynamic> parentItem) {
    setState(() {
      if (_selectedSubIndex == index) {
        _selectedSubIndex = null;
        _activePrice = double.tryParse(parentItem['price'].toString()) ??
            widget.product.price;

        int parentStock = 0;
        for (var s in parentItem['subs']) {
          parentStock += int.tryParse(s['stock'].toString()) ?? 0;
        }
        _activeStock = parentStock;

        if (parentItem['image'] != null &&
            parentItem['image'].toString().isNotEmpty) {
          _currentImage = '${widget.baseUrl}/storage/${parentItem['image']}';
        }
      } else {
        _selectedSubIndex = index;
        _activePrice = double.tryParse(sub['price'].toString()) ??
            double.tryParse(parentItem['price'].toString()) ??
            widget.product.price;
        _activeStock = int.tryParse(sub['stock'].toString()) ?? 0;

        if (sub['image'] != null && sub['image'].toString().isNotEmpty) {
          _currentImage = '${widget.baseUrl}/storage/${sub['image']}';
        }
      }
      _quantity = 1;
    });
  }

  void _validateAndSubmit() {
    if (_hasVariants && _selectedMainIndex == null) {
      _showToast(
          'Please pick a ${widget.product.variants?['title'] ?? 'variant'} first.');
      return;
    }
    if (_hasSubVariants && _selectedSubIndex == null) {
      _showToast(
          'Please pick a ${widget.product.variants?['sub_title'] ?? 'sub-variant'} too.');
      return;
    }
    _showToast('Added to cart successfully!', isError: false);
  }

  void _showToast(String message, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? const Color(0xFFE11D48) : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showImageModal(String imageUrl) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.black.withOpacity(0.9),
          insetPadding: EdgeInsets.zero,
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        foregroundColor: const Color(0xFF292524),
        title: const Text('Product Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
              icon: const Icon(Icons.shopping_cart_outlined), onPressed: () {}),
        ],
      ),
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // Image Gallery block
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          if (_currentImage.isNotEmpty) {
                            _showImageModal(_currentImage);
                          }
                        },
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: _currentImage.isNotEmpty
                              ? Image.network(_currentImage, fit: BoxFit.cover)
                              : const Center(
                                  child: Icon(Icons.image,
                                      size: 80, color: Colors.grey)),
                        ),
                      ),
                      if (widget.product.pictures.length > 1)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: widget.product.pictures.map((pic) {
                              String picUrl = '${widget.baseUrl}/storage/$pic';
                              bool isSelected = _currentImage == picUrl;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _currentImage = picUrl),
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFCF4173)
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(picUrl,
                                        fit: BoxFit.cover),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Product Header Block
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF292524)),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFCF4173).withOpacity(0.05),
                              const Color(0xFFF5F5F4)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFFCF4173).withOpacity(0.1)),
                        ),
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Text(
                              '₱${_discountedActivePrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFCF4173)),
                            ),
                            if (widget.product.discount > 0) ...[
                              Text(
                                '₱${_activePrice.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    fontSize: 16,
                                    decoration: TextDecoration.lineThrough,
                                    color: Color(0xFF78716C)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFE11D48)
                                        .withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(20)),
                                child: Text(
                                    '${widget.product.discount.toStringAsFixed(0)}% OFF',
                                    style: const TextStyle(
                                        color: Color(0xFFE11D48),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ]
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Variants & Quantity Selection Block
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_hasVariants) ...[
                        Text(
                          (widget.product.variants?['title'] ?? 'Variants')
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C)),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(
                            (widget.product.variants!['items'] as List).length,
                            (index) {
                              var item =
                                  widget.product.variants!['items'][index];
                              bool isSelected = _selectedMainIndex == index;
                              return GestureDetector(
                                onTap: () =>
                                    _onMainVariantSelected(index, item),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFCF4173)
                                            .withOpacity(0.1)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFCF4173)
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    item['name'] ?? 'Unnamed',
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFCF4173)
                                          : const Color(0xFF292524),
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      if (_hasSubVariants && _selectedMainIndex != null) ...[
                        Text(
                          (widget.product.variants?['sub_title'] ??
                                  'Sub Variants')
                              .toString()
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C)),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(
                            (widget.product.variants!['items']
                                    [_selectedMainIndex]['subs'] as List)
                                .length,
                            (index) {
                              var sub = widget.product.variants!['items']
                                  [_selectedMainIndex]['subs'][index];
                              var parentItem = widget.product.variants!['items']
                                  [_selectedMainIndex];
                              bool isSelected = _selectedSubIndex == index;
                              return GestureDetector(
                                onTap: () => _onSubVariantSelected(
                                    index, sub, parentItem),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? const Color(0xFFCF4173)
                                            .withOpacity(0.1)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFFCF4173)
                                          : Colors.grey.shade300,
                                      width: isSelected ? 2 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    sub['name'] ?? 'Unnamed',
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFFCF4173)
                                          : const Color(0xFF292524),
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Quantity Selector
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          const Text('QUANTITY',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF78716C))),
                          Container(
                            height: 40,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 16),
                                  onPressed: _quantity > 1
                                      ? () => setState(() => _quantity--)
                                      : null,
                                ),
                                Container(
                                  width: 40,
                                  alignment: Alignment.center,
                                  child: Text('$_quantity',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 16),
                                  onPressed: _quantity < _activeStock
                                      ? () => setState(() => _quantity++)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          Text('$_activeStock pieces available',
                              style: const TextStyle(
                                  color: Color(0xFF78716C), fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Seller Profile Block
                if (widget.product.sellerProfile != null)
                  Container(
                    width: double.infinity,
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor:
                                  const Color(0xFFCF4173).withOpacity(0.1),
                              backgroundImage: widget
                                          .product.sellerProfile!.logoPath !=
                                      null
                                  ? NetworkImage(
                                      '${widget.baseUrl}/storage/${widget.product.sellerProfile!.logoPath}')
                                  : null,
                              child: widget.product.sellerProfile!.logoPath ==
                                      null
                                  ? Text(
                                      widget.product.sellerProfile!.businessName
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFCF4173)),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.product.sellerProfile!.businessName,
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF292524)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.product.sellerProfile!
                                      .lineOfBusiness.isNotEmpty)
                                    Text(
                                      widget.product.sellerProfile!
                                          .lineOfBusiness,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF78716C)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.chat_bubble_outline,
                                    size: 18),
                                label: const Text('Chat Now'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFCF4173),
                                  side: const BorderSide(
                                      color: Color(0xFFCF4173)),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {},
                                icon: const Icon(Icons.storefront, size: 18),
                                label: const Text('View Store'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF292524),
                                  side: BorderSide(color: Colors.grey.shade300),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            _buildSellerStat('Chat Response', '98%'),
                            _buildSellerStat('Ratings', '4.9'),
                            _buildSellerStat('Followers', '128'),
                            _buildSellerStat('Products', '10+'),
                          ],
                        )
                      ],
                    ),
                  ),
                if (widget.product.sellerProfile != null)
                  const SizedBox(height: 8),

                // Specifications Block
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PRODUCT SPECIFICATIONS',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C))),
                      const SizedBox(height: 16),
                      _buildSpecRow('Weight', widget.product.weight),
                      _buildSpecRow('Stock', '$_activeStock'),
                      _buildSpecRow(
                          'Ships From',
                          widget.product.sellerProfile != null
                              ? '${widget.product.sellerProfile!.municipality}, ${widget.product.sellerProfile!.province}'
                              : 'Local Warehouse'),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Description Block
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PRODUCT DESCRIPTION',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF78716C))),
                      const SizedBox(height: 16),
                      Text(
                        widget.product.description.isNotEmpty
                            ? widget.product.description
                            : 'No description available.',
                        style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF292524),
                            height: 1.5),
                      ),
                      if (widget.product.additionalDescriptions != null &&
                          widget
                              .product.additionalDescriptions!.isNotEmpty) ...[
                        const Divider(height: 32),
                        Text(
                          widget.product.additionalDescriptions!,
                          style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF292524),
                              height: 1.5),
                        ),
                      ]
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Suggestions Header
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Text(
                    'You May Also Like',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF292524),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Suggestions Grid
          _suggestedProducts.isEmpty && !_isLoadingSuggestions
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(child: Text('No suggestions available.')),
                  ),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.7,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        return ProductCard(
                          product: _suggestedProducts[index],
                          baseUrl: 'https://dev.storkia.shop',
                          token: widget.token,
                        );
                      },
                      childCount: _suggestedProducts.length,
                    ),
                  ),
                ),

          // Loading Indicator for Suggestions
          if (_isFetchingMoreSuggestions || _isLoadingSuggestions)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFCF4173)),
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),

      // Bottom Actions
      bottomNavigationBar: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _validateAndSubmit,
                  icon: const Icon(Icons.add_shopping_cart,
                      color: Color(0xFFCF4173)),
                  label: const Text('Add To Cart',
                      style: TextStyle(
                          color: Color(0xFFCF4173),
                          fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Color(0xFFCF4173)),
                    backgroundColor: const Color(0xFFCF4173).withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _validateAndSubmit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFFCF4173),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Buy Now',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSellerStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF78716C))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Color(0xFF292524))),
      ],
    );
  }

  Widget _buildSpecRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style:
                      const TextStyle(color: Color(0xFF78716C), fontSize: 14))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      color: Color(0xFF292524),
                      fontSize: 14,
                      fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}
