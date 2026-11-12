import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../models/address_model.dart';

typedef StringMap = Map<String, String>;

class AddressFormScreen extends StatefulWidget {
  final String baseUrl;
  final String token;
  final Address? address;

  const AddressFormScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    this.address,
  });

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _barangayController;
  late TextEditingController _postcodeController;
  late TextEditingController _streetAddressController;
  late TextEditingController _buildingDetailsController;

  bool _isDefault = false;
  bool _isLoadingLocations = true;
  bool _isLoadingMunicipalities = false;
  bool _isLoadingBarangays = false;
  bool _isSubmitting = false;

  List<StringMap> _provinces = [];
  List<StringMap> _municipalities = [];
  List<StringMap> _barangays = [];

  String? _selectedProvinceCode;
  String? _selectedProvinceName;
  String? _selectedMunicipalityCode;
  String? _selectedMunicipalityName;
  String? _selectedBarangayCode;
  String? _selectedBarangayName;

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    final addr = widget.address;

    _firstNameController = TextEditingController(text: addr?.firstName ?? '');
    _lastNameController = TextEditingController(text: addr?.lastName ?? '');

    String phoneText = addr?.phoneNumber ?? '';
    if (phoneText.startsWith('+63')) {
      phoneText = phoneText.substring(3).trim();
    } else if (phoneText.startsWith('63') && phoneText.length == 12) {
      phoneText = phoneText.substring(2).trim();
    } else if (phoneText.startsWith('0')) {
      phoneText = phoneText.substring(1).trim();
    }
    _phoneController = TextEditingController(text: phoneText);

    _barangayController = TextEditingController(text: addr?.barangay ?? '');
    _postcodeController = TextEditingController(text: addr?.postcode ?? '');
    _streetAddressController =
        TextEditingController(text: addr?.streetAddress ?? '');
    _buildingDetailsController =
        TextEditingController(text: addr?.buildingDetails ?? '');
    _isDefault = addr?.isDefault ?? false;

    if (addr != null) {
      _selectedProvinceCode = addr.provinceCode;
      _selectedProvinceName = addr.province;
      _selectedMunicipalityCode = addr.municipalityCode;
      _selectedMunicipalityName = addr.municipality;
      _selectedBarangayCode = addr.barangayCode;
      _selectedBarangayName = addr.barangay;
    }

    _fetchProvinces();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _barangayController.dispose();
    _postcodeController.dispose();
    _streetAddressController.dispose();
    _buildingDetailsController.dispose();
    super.dispose();
  }

  Future<void> _fetchProvinces() async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/addresses/provinces'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final List<dynamic> rawList = data['data'] as List<dynamic>;
          setState(() {
            _provinces = [
              for (final item in rawList)
                if (item is Map)
                  {
                    'code':
                        (item['code'] ?? item['province_code'] ?? item['id'])
                            .toString(),
                    'name':
                        (item['name'] ?? item['province_name'] ?? item['title'])
                            .toString(),
                  },
            ];
            _isLoadingLocations = false;
          });

          if (_selectedProvinceCode != null &&
              _selectedProvinceCode!.isNotEmpty) {
            await _fetchMunicipalities(
              _selectedProvinceCode!,
              preserveSelection: true,
            );
          }
          return;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoadingLocations = false);
    }
  }

  Future<void> _fetchMunicipalities(
    String provinceCode, {
    bool preserveSelection = false,
  }) async {
    setState(() {
      _isLoadingMunicipalities = true;
      _municipalities = [];
      if (!preserveSelection) {
        _barangays = [];
      }
    });

    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/addresses/municipalities/$provinceCode'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final List<dynamic> rawList = data['data'] as List<dynamic>;
          setState(() {
            _municipalities = [
              for (final item in rawList)
                if (item is Map)
                  {
                    'code': (item['code'] ??
                            item['municipality_code'] ??
                            item['id'])
                        .toString(),
                    'name': (item['name'] ??
                            item['municipality_name'] ??
                            item['title'])
                        .toString(),
                  },
            ];
          });

          if (preserveSelection &&
              _selectedMunicipalityCode != null &&
              _selectedMunicipalityCode!.isNotEmpty) {
            await _fetchBarangays(
              _selectedMunicipalityCode!,
              preserveSelection: true,
            );
          }
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingMunicipalities = false);
    }
  }

  Future<void> _fetchBarangays(
    String municipalityCode, {
    bool preserveSelection = false,
  }) async {
    setState(() {
      _isLoadingBarangays = true;
      _barangays = [];
    });

    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/addresses/barangays/$municipalityCode'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] is List) {
          final List<dynamic> rawList = data['data'] as List<dynamic>;
          final List<StringMap> parsed = [
            for (final item in rawList)
              if (item is Map)
                {
                  'code': (item['code'] ??
                          item['barangay_code'] ??
                          item['id'] ??
                          '')
                      .toString(),
                  'name': (item['name'] ??
                          item['barangay_name'] ??
                          item['title'] ??
                          '')
                      .toString(),
                },
          ];

          setState(() {
            _barangays = parsed;
            if (preserveSelection &&
                _selectedBarangayName != null &&
                _selectedBarangayName!.isNotEmpty) {
              final match = parsed.firstWhere(
                (b) =>
                    b['code'] == _selectedBarangayCode ||
                    b['name']!.toLowerCase() ==
                        _selectedBarangayName!.toLowerCase(),
                orElse: () => <String, String>{},
              );
              if (match.isNotEmpty) {
                _selectedBarangayCode = match['code'];
                _selectedBarangayName = match['name'];
                _barangayController.text = match['name']!;
              }
            }
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingBarangays = false);
    }
  }

  Future<void> _saveAddress() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProvinceCode == null || _selectedProvinceName == null) {
      _showError('Please select a province.');
      return;
    }
    if (_selectedMunicipalityCode == null ||
        _selectedMunicipalityName == null) {
      _showError('Please select a municipality or city.');
      return;
    }

    final String resolvedBarangay = (_selectedBarangayName != null &&
            _selectedBarangayName!.trim().isNotEmpty)
        ? _selectedBarangayName!.trim()
        : _barangayController.text.trim();

    if (resolvedBarangay.isEmpty) {
      _showError('Please select or enter your barangay.');
      return;
    }

    setState(() => _isSubmitting = true);

    final isEditing = widget.address != null;
    final url = isEditing
        ? '$_domain/api/v1/addresses/${widget.address!.id}'
        : '$_domain/api/v1/addresses';

    final payload = {
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'province_code': _selectedProvinceCode,
      'province': _selectedProvinceName,
      'municipality_code': _selectedMunicipalityCode,
      'municipality': _selectedMunicipalityName,
      'barangay_code': _selectedBarangayCode,
      'barangay': resolvedBarangay,
      'postcode': _postcodeController.text.trim(),
      'street_address': _streetAddressController.text.trim(),
      'building_details': _buildingDetailsController.text.trim().isNotEmpty
          ? _buildingDetailsController.text.trim()
          : null,
      'is_default': _isDefault,
    };

    try {
      final response = isEditing
          ? await http
              .put(
                Uri.parse(url),
                headers: {
                  'Authorization': 'Bearer ${widget.token}',
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                body: json.encode(payload),
              )
              .timeout(ApiConfig.requestTimeout)
          : await http
              .post(
                Uri.parse(url),
                headers: {
                  'Authorization': 'Bearer ${widget.token}',
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
                body: json.encode(payload),
              )
              .timeout(ApiConfig.requestTimeout);

      final data = json.decode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data['success'] == true) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Address saved successfully!'),
                backgroundColor: StorkTheme.success,
              ),
            );
            Navigator.pop(context, true);
          }
          return;
        }
      }

      String errorMsg = data['message'] ?? 'Failed to save address.';
      if (data['errors'] != null && data['errors'] is Map) {
        final Map errors = data['errors'];
        if (errors.isNotEmpty) {
          errorMsg = errors.values.first[0].toString();
        }
      }
      _showError(errorMsg);
    } catch (_) {
      _showError('Network error occurred while saving address.');
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
    final isEditing = widget.address != null;
    final String? validProvinceValue =
        _provinces.any((p) => p['code'] == _selectedProvinceCode)
            ? _selectedProvinceCode
            : null;
    final String? validMunicipalityValue =
        _municipalities.any((m) => m['code'] == _selectedMunicipalityCode)
            ? _selectedMunicipalityCode
            : null;
    final String? validBarangayValue =
        _barangays.any((b) => b['code'] == _selectedBarangayCode)
            ? _selectedBarangayCode
            : null;

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Address' : 'Add New Address'),
      ),
      body: _isLoadingLocations
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionCard(
                    title: 'Recipient Contact Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _firstNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'First Name*',
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                      ? 'Required'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _lastNameController,
                              textCapitalization: TextCapitalization.words,
                              decoration: const InputDecoration(
                                labelText: 'Last Name*',
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                      ? 'Required'
                                      : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Phone Number*',
                          prefixText: '+63 ',
                          hintText: '9123456789',
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Phone number is required';
                          }
                          final clean =
                              val.trim().replaceAll(RegExp(r'\D'), '');
                          if (!RegExp(r'^9\d{9}$').hasMatch(clean)) {
                            return 'Enter a valid 10-digit number starting with 9';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildSectionCard(
                    title: 'PSGC Delivery Location',
                    children: [
                      DropdownButtonFormField<String>(
                        key: ValueKey('prov_${validProvinceValue ?? 'none'}'),
                        isExpanded: true,
                        initialValue: validProvinceValue,
                        decoration: const InputDecoration(
                          labelText: 'Province*',
                        ),
                        items: _provinces.map((p) {
                          return DropdownMenuItem<String>(
                            value: p['code'],
                            child: Text(
                              p['name']!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          final match =
                              _provinces.firstWhere((p) => p['code'] == value);
                          setState(() {
                            _selectedProvinceCode = value;
                            _selectedProvinceName = match['name'];
                            _selectedMunicipalityCode = null;
                            _selectedMunicipalityName = null;
                            _selectedBarangayCode = null;
                            _selectedBarangayName = null;
                            _barangayController.clear();
                          });
                          _fetchMunicipalities(value);
                        },
                        validator: (val) =>
                            val == null ? 'Please select a province' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        key: ValueKey(
                            'mun_${_selectedProvinceCode ?? ''}_${validMunicipalityValue ?? 'none'}'),
                        isExpanded: true,
                        initialValue: validMunicipalityValue,
                        decoration: InputDecoration(
                          labelText: 'Municipality / City*',
                          suffixIcon: _isLoadingMunicipalities
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: StorkTheme.primary,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        items: _municipalities.map((m) {
                          return DropdownMenuItem<String>(
                            value: m['code'],
                            child: Text(
                              m['name']!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: _selectedProvinceCode == null
                            ? null
                            : (value) {
                                if (value == null) return;
                                final match = _municipalities
                                    .firstWhere((m) => m['code'] == value);
                                setState(() {
                                  _selectedMunicipalityCode = value;
                                  _selectedMunicipalityName = match['name'];
                                  _selectedBarangayCode = null;
                                  _selectedBarangayName = null;
                                  _barangayController.clear();
                                });
                                _fetchBarangays(value);
                              },
                        validator: (val) =>
                            val == null ? 'Please select a municipality' : null,
                      ),
                      const SizedBox(height: 14),
                      if (_barangays.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey(
                              'brgy_${_selectedMunicipalityCode ?? ''}_${validBarangayValue ?? 'none'}'),
                          isExpanded: true,
                          initialValue: validBarangayValue,
                          decoration: InputDecoration(
                            labelText: 'Barangay*',
                            suffixIcon: _isLoadingBarangays
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: StorkTheme.primary,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          items: _barangays.map((b) {
                            return DropdownMenuItem<String>(
                              value: b['code'],
                              child: Text(
                                b['name']!,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            final match = _barangays
                                .firstWhere((b) => b['code'] == value);
                            setState(() {
                              _selectedBarangayCode = value;
                              _selectedBarangayName = match['name'];
                              _barangayController.text = match['name']!;
                            });
                          },
                          validator: (val) =>
                              val == null ? 'Please select a barangay' : null,
                        )
                      else
                        TextFormField(
                          controller: _barangayController,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Barangay*',
                            suffixIcon: _isLoadingBarangays
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Padding(
                                      padding: EdgeInsets.all(12),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: StorkTheme.primary,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          validator: (val) => val == null || val.trim().isEmpty
                              ? 'Required'
                              : null,
                        ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _postcodeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Postal / Zip Code*',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _streetAddressController,
                        decoration: const InputDecoration(
                          labelText: 'Street Name, Building, House No.*',
                        ),
                        validator: (val) => val == null || val.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _buildingDetailsController,
                        decoration: const InputDecoration(
                          labelText: 'Unit / Floor / Landmark (Optional)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: StorkTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: StorkTheme.borderSubtle),
                    ),
                    child: SwitchListTile(
                      activeThumbColor: StorkTheme.primary,
                      title: const Text(
                        'Set as Default Delivery Address',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      value: _isDefault,
                      onChanged: (val) => setState(() => _isDefault = val),
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _saveAddress,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(isEditing ? 'Update Address' : 'Save Address'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
