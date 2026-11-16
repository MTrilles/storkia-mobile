import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/address_model.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import 'address_form_screen.dart';

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

class _AddressSelectionScreenState extends State<AddressSelectionScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  List<Address> _addresses = [];
  int? _currentSelectedId;
  final Set<int> _expandedAddressIds = <int>{};

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentSelectedId = widget.selectedAddressId;
    _fetchAddresses(silent: false);
    WebSocketService.addListener(_onRealtimeEvent);
  }

  void _onRealtimeEvent(BuyerRealtimeEvent event) {
    if (!mounted) return;
    if (event.scope == 'address' || event.scope == 'user') {
      _fetchAddresses(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebSocketService.removeListener(_onRealtimeEvent);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchAddresses(silent: true);
    }
  }

  Future<void> _copyAddressToClipboard(Address address) async {
    final formatted =
        '${address.recipientName} (${address.phoneNumber}) - ${address.fullAddress}';
    await Clipboard.setData(ClipboardData(text: formatted));
    HapticFeedback.lightImpact();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Delivery address copied to clipboard!'),
        backgroundColor: StorkTheme.primaryDark,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _fetchAddresses({bool silent = true}) async {
    if (!silent && _addresses.isEmpty) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await ApiService.httpClient
          .get(
            Uri.parse('$_domain/api/v1/addresses'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final List<dynamic> raw = data['data'] as List<dynamic>;
          setState(() {
            _addresses = [
              for (final item in raw)
                if (item is Map) Address.fromJson(JsonMap.from(item)),
            ];
            _isLoading = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted && !silent) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load addresses.')),
      );
    }
  }

  Future<void> _setDefaultAddress(Address address) async {
    HapticFeedback.selectionClick();
    try {
      final response = await ApiService.httpClient
          .patch(
            Uri.parse('$_domain/api/v1/addresses/${address.id}/default'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        _fetchAddresses(silent: true);
      }
    } catch (_) {}
  }

  Future<void> _deleteAddress(Address address) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text(
          'Delete Address',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: const Text(
          'Are you sure you want to delete this address? This action cannot be undone.',
          style: TextStyle(fontSize: 13.5, color: StorkTheme.textMain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: StorkTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: StorkTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _addresses.removeWhere((a) => a.id == address.id);
    });

    try {
      final response = await ApiService.httpClient
          .delete(
            Uri.parse('$_domain/api/v1/addresses/${address.id}'),
            headers: ApiService.buildHeaders(widget.token),
          )
          .timeout(ApiConfig.requestTimeout);

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address deleted successfully.'),
              backgroundColor: StorkTheme.success,
            ),
          );
        }
        _fetchAddresses(silent: true);
      } else {
        _fetchAddresses(silent: true);
        _showError(data['message'] ?? 'Failed to delete address.');
      }
    } catch (_) {
      _fetchAddresses(silent: true);
      _showError('Network error occurred.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: StorkTheme.danger),
    );
  }

  Future<void> _navigateToAddOrEdit([Address? address]) async {
    final refreshed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AddressFormScreen(
          baseUrl: _domain,
          token: widget.token,
          address: address,
        ),
      ),
    );
    if (refreshed == true) {
      _fetchAddresses(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('Address Book (${_addresses.length})'),
        ),
      ),
      body: _isLoading && _addresses.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : _addresses.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: StorkTheme.primary,
                  onRefresh: () => _fetchAddresses(silent: true),
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _addresses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final address = _addresses[index];
                      final isSelected = address.id == _currentSelectedId;
                      final isExpanded =
                          _expandedAddressIds.contains(address.id);
                      final isLongAddress = address.fullAddress.length > 85;

                      return InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _currentSelectedId = address.id);
                          Navigator.pop(context, address);
                        },
                        onLongPress: () => _copyAddressToClipboard(address),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? StorkTheme.primary.withValues(alpha: 0.05)
                                : StorkTheme.surface,
                            border: Border.all(
                              color: !address.isServiceable
                                  ? StorkTheme.danger.withValues(alpha: 0.5)
                                  : (isSelected
                                      ? StorkTheme.primary
                                      : StorkTheme.borderSubtle),
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.025),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? StorkTheme.primary
                                          : StorkTheme.primary
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isSelected
                                          ? Icons.check_rounded
                                          : Icons.location_on_outlined,
                                      color: isSelected
                                          ? Colors.white
                                          : StorkTheme.primary,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Wrap(
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: [
                                            Text(
                                              address.recipientName,
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: StorkTheme.textMain,
                                              ),
                                            ),
                                            if (address.isDefault)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  gradient:
                                                      const LinearGradient(
                                                    colors: [
                                                      StorkTheme.primaryDark,
                                                      StorkTheme.primary,
                                                    ],
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: const Text(
                                                  'DEFAULT',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: 0.4,
                                                  ),
                                                ),
                                              ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2.5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: address.isServiceable
                                                    ? StorkTheme.success
                                                        .withValues(alpha: 0.12)
                                                    : StorkTheme.danger
                                                        .withValues(
                                                            alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                address.isServiceable
                                                    ? 'Serviceable Zone'
                                                    : 'Outside Rider Coverage',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w800,
                                                  color: address.isServiceable
                                                      ? StorkTheme.success
                                                      : StorkTheme.danger,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          address.phoneNumber,
                                          style: const TextStyle(
                                            color: StorkTheme.textMuted,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    tooltip: 'Copy Address',
                                    onPressed: () =>
                                        _copyAddressToClipboard(address),
                                    icon: const Icon(
                                      Icons.copy_all_rounded,
                                      size: 17,
                                      color: StorkTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: StorkTheme.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      address.fullAddress,
                                      maxLines:
                                          isLongAddress && !isExpanded ? 2 : 10,
                                      overflow: isLongAddress && !isExpanded
                                          ? TextOverflow.ellipsis
                                          : TextOverflow.visible,
                                      style: const TextStyle(
                                        color: StorkTheme.textMain,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                    if (isLongAddress) ...[
                                      const SizedBox(height: 4),
                                      GestureDetector(
                                        onTap: () {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedAddressIds
                                                  .remove(address.id);
                                            } else {
                                              _expandedAddressIds
                                                  .add(address.id);
                                            }
                                          });
                                        },
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              isExpanded
                                                  ? 'See Less'
                                                  : 'See More',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                                color: StorkTheme.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(
                                              isExpanded
                                                  ? Icons
                                                      .keyboard_arrow_up_rounded
                                                  : Icons
                                                      .keyboard_arrow_down_rounded,
                                              size: 15,
                                              color: StorkTheme.primary,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  if (!address.isDefault)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _setDefaultAddress(address),
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      icon: const Icon(
                                        Icons.star_border_rounded,
                                        size: 16,
                                        color: StorkTheme.primaryDark,
                                      ),
                                      label: const Text(
                                        'Set Default',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: StorkTheme.primaryDark,
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox.shrink(),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      TextButton.icon(
                                        onPressed: () =>
                                            _navigateToAddOrEdit(address),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          size: 16,
                                          color: StorkTheme.primary,
                                        ),
                                        label: const Text(
                                          'Edit',
                                          style: TextStyle(
                                            color: StorkTheme.primary,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () =>
                                            _deleteAddress(address),
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                          size: 16,
                                          color: StorkTheme.danger,
                                        ),
                                        label: const Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: StorkTheme.danger,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: StorkTheme.surface,
          border: const Border(top: BorderSide(color: StorkTheme.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () => _navigateToAddOrEdit(),
              icon: const Icon(Icons.add_location_alt_outlined,
                  color: Colors.white),
              label: const Text(
                'Add New Address',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: StorkTheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_outlined,
                size: 38,
                color: StorkTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Saved Addresses Yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: StorkTheme.primaryDark,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add a PSGC-verified delivery address to start checking out your favorite items.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: StorkTheme.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
