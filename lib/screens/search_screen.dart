import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/product_model.dart';
import '../components/product_card.dart';

class SearchScreen extends StatefulWidget {
  final String baseUrl;
  final String? token;

  const SearchScreen({super.key, required this.baseUrl, this.token});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<dynamic> _suggestions = [];
  bool _isSearching = false;

  List<Product> _results = [];
  bool _hasSearched = false;
  bool _isLoadingResults = false;

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (query.length < 2) {
      setState(() => _suggestions = []);
      return;
    }

    // Debounce to avoid flooding the API while typing
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final response = await http.get(
          Uri.parse('${widget.baseUrl}/api/v1/search/suggestions?q=$query'),
          headers: {'Accept': 'application/json'},
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          setState(() {
            _suggestions = data['data'] ?? [];
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _performSearch(String query, {String? category}) async {
    FocusScope.of(context).unfocus(); // Hide keyboard
    setState(() {
      _isSearching = false;
      _hasSearched = true;
      _isLoadingResults = true;
      _suggestions = [];
    });

    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/api/v1/search?q=$query${category != null && category.isNotEmpty ? '&category=$category' : ''}');
      final response =
          await http.get(uri, headers: {'Accept': 'application/json'});

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List items = data['data']['data'];
        setState(() {
          _results = items.map((json) => Product.fromJson(json)).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingResults = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            onChanged: (val) {
              setState(() => _isSearching = true);
              _onSearchChanged(val);
            },
            onSubmitted: (val) => _performSearch(val),
            decoration: InputDecoration(
              hintText: 'Search for products, categories...',
              hintStyle:
                  const TextStyle(fontSize: 14, color: Color(0xFF78716C)),
              filled: true,
              fillColor: const Color(0xFFF5F5F4),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _suggestions = [];
                          _isSearching = false;
                        });
                      },
                    )
                  : null,
            ),
          ),
        ),
      ),
      body: _isSearching
          ? _buildSuggestions()
          : _hasSearched
              ? _buildResults()
              : const Center(
                  child: Text('Type to start searching',
                      style: TextStyle(color: Color(0xFF78716C)))),
    );
  }

  Widget _buildSuggestions() {
    if (_suggestions.isEmpty) {
      if (_searchController.text.length >= 2) {
        return const Center(
            child: CircularProgressIndicator(color: Color(0xFFCF4173)));
      }
      return const SizedBox.shrink();
    }

    return ListView.separated(
      itemCount: _suggestions.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final sug = _suggestions[index];
        final name = sug['name'];
        final category = sug['category'];

        return ListTile(
          tileColor: Colors.white,
          leading: const Icon(Icons.search, color: Color(0xFF78716C), size: 20),
          title: RichText(
            text: TextSpan(
              style: const TextStyle(color: Color(0xFF292524), fontSize: 14),
              children: [
                TextSpan(text: name),
                if (category.isNotEmpty) ...[
                  const TextSpan(
                      text: ' in ', style: TextStyle(color: Color(0xFF78716C))),
                  TextSpan(
                      text: category,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFCF4173))),
                ]
              ],
            ),
          ),
          onTap: () {
            _searchController.text = name;
            _performSearch(name, category: category);
          },
        );
      },
    );
  }

  Widget _buildResults() {
    if (_isLoadingResults) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFFCF4173)));
    }

    if (_results.isEmpty) {
      return const Center(child: Text('No products found.'));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        return ProductCard(
          product: _results[index],
          baseUrl: widget.baseUrl,
          token: widget.token ?? '',
        );
      },
    );
  }
}
