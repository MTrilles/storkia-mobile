import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/address_model.dart';

class AddressSelectionScreen extends StatefulWidget {
  final String baseUrl;
  final String token;
  final int? selectedAddressId;

  const AddressSelectionScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    this.selectedAddressId,
  });

  @override
  State<AddressSelectionScreen> createState() => _AddressSelectionScreenState();
}

class _AddressSelectionScreenState extends State<AddressSelectionScreen> {
  bool _isLoading = true;
  List<Address> _addresses = [];
  int? _currentSelectedId;

  @override
  void initState() {
    super.initState();
    _currentSelectedId = widget.selectedAddressId;
    _fetchAddresses();
  }

  Future<void> _fetchAddresses() async {
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/api/v1/addresses'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          setState(() {
            _addresses = (data['data'] as List)
                .map((item) => Address.fromJson(item))
                .toList();
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load addresses.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF292524),
        elevation: 0.5,
        title: const Text('Select Delivery Address',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFCF4173)))
          : _addresses.isEmpty
              ? const Center(child: Text('No addresses found. Add one.'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _addresses.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final address = _addresses[index];
                    final isSelected = address.id == _currentSelectedId;

                    return GestureDetector(
                      onTap: () {
                        setState(() => _currentSelectedId = address.id);
                        Navigator.pop(context, address);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFCF4173).withOpacity(0.05)
                              : Colors.white,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFCF4173)
                                : Colors.grey.shade300,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  address.recipientName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF292524),
                                  ),
                                ),
                                if (address.isDefault)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFCF4173),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('Default',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold)),
                                  )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(address.phoneNumber,
                                style: const TextStyle(
                                    color: Color(0xFF78716C), fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(address.fullAddress,
                                style: const TextStyle(
                                    color: Color(0xFF292524),
                                    fontSize: 14,
                                    height: 1.4)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
