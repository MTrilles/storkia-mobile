import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../components/daily_chest_floating_button.dart';
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';

typedef JsonMap = Map<String, dynamic>;

class PointsRewardsScreen extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;
  final int initialTab;

  const PointsRewardsScreen({
    super.key,
    required this.baseUrl,
    required this.token,
    this.initialTab = 0,
  });

  @override
  ConsumerState<PointsRewardsScreen> createState() =>
      _PointsRewardsScreenState();
}

class _PointsRewardsScreenState extends ConsumerState<PointsRewardsScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  late AnimationController _wheelController;
  double _wheelRotationRadians = 0.0;

  Timer? _autoSyncTimer;
  bool _isLoading = true;
  bool _isSpinning = false;
  String? _redeemingKey;
  bool _isSubmittingTopup = false;

  JsonMap _walletInfo = {
    'coins_balance': 0,
    'coins_peso_equivalent': 0.0,
    'lifetime_coins_earned': 0,
    'lifetime_coins_spent': 0,
    'spin_tickets': 0,
  };
  JsonMap _chestInfo = {
    'can_open': false,
    'cooldown_sec': 0,
  };
  JsonMap _buyerEwallet = {
    'available_balance': 0.0,
    'pending_balance': 0.0,
    'total_earned': 0.0,
    'total_withdrawn': 0.0,
  };
  JsonMap? _platformGcash;
  List<JsonMap> _wheelSegments = [];
  List<JsonMap> _redeemCatalog = [];
  List<JsonMap> _rewardTransactions = [];
  List<JsonMap> _topupSubmissions = [];
  List<JsonMap> _walletTransactions = [];

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _wheelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );
    _loadAllData();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _loadAllData(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSyncTimer?.cancel();
    _tabController.dispose();
    _wheelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAllData(silent: true);
    }
  }

  String _formatMoney(dynamic raw) {
    final val = double.tryParse(raw?.toString() ?? '0') ?? 0.0;
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
    return '$intPart.${parts[1]}';
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return 'Ready Now!';
    final h = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _loadAllData({bool silent = false}) async {
    if (!silent) {
      setState(() => _isLoading = true);
    }
    try {
      final results = await Future.wait([
        http.get(
          Uri.parse('$_domain/api/v1/rewards'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Accept': 'application/json',
          },
        ).timeout(ApiConfig.requestTimeout),
        http.get(
          Uri.parse('$_domain/api/v1/wallet'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Accept': 'application/json',
          },
        ).timeout(ApiConfig.requestTimeout),
        http.get(
          Uri.parse('$_domain/api/v1/rewards/transactions?per_page=20'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Accept': 'application/json',
          },
        ).timeout(ApiConfig.requestTimeout),
      ]);

      if (!mounted) return;

      final rewardsRes = results[0];
      final walletRes = results[1];
      final txRes = results[2];

      if (rewardsRes.statusCode == 200) {
        final body = json.decode(rewardsRes.body);
        if (body is Map && body['success'] == true && body['data'] is Map) {
          final d = Map<String, dynamic>.from(body['data'] as Map);
          if (d['wallet'] is Map) {
            _walletInfo = Map<String, dynamic>.from(d['wallet'] as Map);
          }
          if (d['chest'] is Map) {
            _chestInfo = Map<String, dynamic>.from(d['chest'] as Map);
          }
          if (d['buyer_ewallet'] is Map) {
            _buyerEwallet =
                Map<String, dynamic>.from(d['buyer_ewallet'] as Map);
          }
          if (d['platform_gcash'] is Map) {
            _platformGcash =
                Map<String, dynamic>.from(d['platform_gcash'] as Map);
          }
          if (d['wheel_segments'] is List) {
            final List<dynamic> rawSegs =
                List<dynamic>.from(d['wheel_segments'] as List);
            _wheelSegments = [
              for (final e in rawSegs)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
          if (d['redeem_catalog'] is List) {
            final List<dynamic> rawCat =
                List<dynamic>.from(d['redeem_catalog'] as List);
            _redeemCatalog = [
              for (final e in rawCat)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
        }
      }

      if (walletRes.statusCode == 200) {
        final body = json.decode(walletRes.body);
        if (body is Map && body['success'] == true && body['data'] is Map) {
          final d = Map<String, dynamic>.from(body['data'] as Map);
          if (d['buyer_ewallet'] is Map) {
            _buyerEwallet =
                Map<String, dynamic>.from(d['buyer_ewallet'] as Map);
          }
          if (d['platform_gcash'] is Map) {
            _platformGcash =
                Map<String, dynamic>.from(d['platform_gcash'] as Map);
          }
          if (d['topups'] is List) {
            final List<dynamic> rawTopups =
                List<dynamic>.from(d['topups'] as List);
            _topupSubmissions = [
              for (final e in rawTopups)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
          if (d['transactions'] is List) {
            final List<dynamic> rawWtx =
                List<dynamic>.from(d['transactions'] as List);
            _walletTransactions = [
              for (final e in rawWtx)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
        }
      }

      if (txRes.statusCode == 200) {
        final body = json.decode(txRes.body);
        if (body is Map && body['success'] == true && body['data'] is Map) {
          final paginator = Map<String, dynamic>.from(body['data'] as Map);
          if (paginator['data'] is List) {
            final List<dynamic> rawRtx =
                List<dynamic>.from(paginator['data'] as List);
            _rewardTransactions = [
              for (final e in rawRtx)
                if (e is Map) Map<String, dynamic>.from(e),
            ];
          }
        }
      }

      ref
          .read(rewardSummaryProvider.notifier)
          .fetchRewardAndWalletSummary(widget.token);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _spinWheel() async {
    final int tickets =
        int.tryParse(_walletInfo['spin_tickets']?.toString() ?? '0') ?? 0;
    if (_isSpinning || tickets <= 0) return;

    setState(() => _isSpinning = true);

    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/rewards/spin'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        final int segmentIndex =
            int.tryParse(data['segment_index']?.toString() ?? '0') ?? 0;
        final int totalSegments =
            _wheelSegments.isNotEmpty ? _wheelSegments.length : 8;
        final double sliceAngle = (2 * math.pi) / totalSegments;
        final double targetSegmentCenter =
            (segmentIndex * sliceAngle) + (sliceAngle / 2);
        final double targetAngle =
            (_wheelRotationRadians - (_wheelRotationRadians % (2 * math.pi))) +
                (6 * 2 * math.pi) +
                ((2 * math.pi) - targetSegmentCenter) -
                (math.pi / 2);

        final double startAngle = _wheelRotationRadians;
        final Animation<double> curve = CurvedAnimation(
          parent: _wheelController,
          curve: Curves.easeOutQuart,
        );

        void listener() {
          if (mounted) {
            setState(() {
              _wheelRotationRadians =
                  startAngle + ((targetAngle - startAngle) * curve.value);
            });
          }
        }

        _wheelController.addListener(listener);
        await _wheelController.forward(from: 0.0);
        _wheelController.removeListener(listener);

        if (!mounted) return;

        final int newCoins =
            int.tryParse(data['coins_balance']?.toString() ?? '0') ?? 0;
        final int newSpins =
            int.tryParse(data['spin_tickets']?.toString() ?? '0') ?? 0;
        final int nextSpinSec =
            int.tryParse(data['next_daily_spin_sec']?.toString() ?? '0') ?? 0;

        ref.read(rewardSummaryProvider.notifier).applySpinOrRedeemUpdate(
              coinsBalance: newCoins,
              spinTickets: newSpins,
              dailySpinCooldownSec: nextSpinSec,
            );

        setState(() {
          _walletInfo['coins_balance'] = newCoins;
          _walletInfo['coins_peso_equivalent'] = newCoins * 0.10;
          _walletInfo['spin_tickets'] = newSpins;
          _isSpinning = false;
        });

        _showSpinRewardDialog(
          title: data['segment']?['label']?.toString() ?? 'Reward Unlocked!',
          message: data['message']?.toString() ?? 'Added to your account!',
          voucherCode: data['voucher']?['code']?.toString(),
        );
        _loadAllData(silent: true);
      } else {
        setState(() => _isSpinning = false);
        _showToast(
          data is Map
              ? (data['message']?.toString() ?? 'Unable to spin right now.')
              : 'Unable to spin right now.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSpinning = false);
        _showToast('Network error occurred while spinning.');
      }
    }
  }

  void _showSpinRewardDialog({
    required String title,
    required String message,
    String? voucherCode,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: StorkTheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: StorkTheme.primaryDark,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontSize: 13.5,
                color: StorkTheme.textMain,
                height: 1.4,
              ),
            ),
            if (voucherCode != null && voucherCode.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: StorkTheme.brandLight.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: StorkTheme.borderSubtle),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Code: $voucherCode',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: voucherCode));
                        _showToast('Voucher code copied!', isError: false);
                      },
                      child: const Text('Copy'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Awesome!'),
          ),
        ],
      ),
    );
  }

  Future<void> _redeemVoucherWithCoins(JsonMap item) async {
    final String key = item['key']?.toString() ?? '';
    final int cost = int.tryParse(item['coins_cost']?.toString() ?? '0') ?? 0;
    final String title = item['title']?.toString() ?? 'Voucher';
    if (key.isEmpty || _redeemingKey != null) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Redeem Coins for Voucher?',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        content: Text(
          'Spend $cost Storkia Coins to claim "$title"? It will be added directly to your Voucher Wallet for checkout.',
          style: const TextStyle(fontSize: 13.5, color: StorkTheme.textMain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: StorkTheme.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Redeem ($cost Coins)'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _redeemingKey = key);
    try {
      final response = await http
          .post(
            Uri.parse('$_domain/api/v1/rewards/redeem'),
            headers: {
              'Authorization': 'Bearer ${widget.token}',
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: json.encode({'catalog_key': key}),
          )
          .timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final data = json.decode(response.body);

      if (response.statusCode == 200 &&
          data is Map &&
          data['success'] == true) {
        final int newCoins =
            int.tryParse(data['coins_balance']?.toString() ?? '0') ?? 0;
        ref.read(rewardSummaryProvider.notifier).applySpinOrRedeemUpdate(
              coinsBalance: newCoins,
            );
        _showToast(
          data['message']?.toString() ??
              'Voucher redeemed and added to wallet!',
          isError: false,
        );
        _loadAllData(silent: true);
      } else {
        _showToast(
          data is Map
              ? (data['message']?.toString() ?? 'Unable to redeem voucher.')
              : 'Unable to redeem voucher.',
        );
      }
    } catch (_) {
      _showToast('Network error occurred.');
    } finally {
      if (mounted) setState(() => _redeemingKey = null);
    }
  }

  Future<void> _openTopUpModal() async {
    final senderNameCtrl = TextEditingController();
    final senderPhoneCtrl = TextEditingController();
    final refNumCtrl = TextEditingController();
    XFile? receiptFile;
    bool showQr = false;
    String? modalError;

    final String adminGcashName =
        _platformGcash?['account_name']?.toString() ?? 'Storkia Admin Escrow';
    final String adminGcashNumber =
        _platformGcash?['gcash_number']?.toString() ?? '09171234567';
    final String qrUrl = _platformGcash?['qr_image_url']?.toString() ??
        (_platformGcash?['qr_image_path'] != null
            ? ApiConfig.storageUrl(
                _platformGcash!['qr_image_path'].toString(), _domain)
            : '');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            void sanitizePhone(String val) {
              String digits = val.replaceAll(RegExp(r'\D'), '');
              if (digits.startsWith('63') && digits.length == 12) {
                digits = '0${digits.substring(2)}';
              } else if (digits.startsWith('9') && digits.length == 10) {
                digits = '0$digits';
              }
              if (digits.length > 11) {
                digits = digits.substring(0, 11);
              }
              if (senderPhoneCtrl.text != digits) {
                senderPhoneCtrl.value = TextEditingValue(
                  text: digits,
                  selection: TextSelection.collapsed(offset: digits.length),
                );
              }
            }

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
                        const Expanded(
                          child: Text(
                            'Top Up Storkia E-Wallet via GCash',
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
                    const Text(
                      'Send your desired amount to Storkia Admin Escrow via GCash, then upload the receipt screenshot. Admin will verify the screenshot and credit the exact Peso amount to your E-Wallet.',
                      style: TextStyle(
                        fontSize: 12,
                        color: StorkTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: StorkTheme.info.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: StorkTheme.info.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'STORKIA ADMIN GCASH ESCROW',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: StorkTheme.info,
                                ),
                              ),
                              if (qrUrl.isNotEmpty)
                                TextButton(
                                  onPressed: () =>
                                      setModalState(() => showQr = !showQr),
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  child: Text(
                                    showQr ? 'Hide QR' : 'Show QR Code',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Account Name: $adminGcashName',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: StorkTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'GCash Number: $adminGcashNumber',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: StorkTheme.info,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                onPressed: () {
                                  Clipboard.setData(
                                      ClipboardData(text: adminGcashNumber));
                                  _showToast('GCash number copied!',
                                      isError: false);
                                },
                              ),
                            ],
                          ),
                          if (showQr && qrUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.network(
                                  qrUrl,
                                  width: 180,
                                  height: 180,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: senderNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'GCash Sender Account Name *',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: senderPhoneCtrl,
                            keyboardType: TextInputType.phone,
                            maxLength: 11,
                            onChanged: sanitizePhone,
                            decoration: const InputDecoration(
                              labelText: 'Sender Mobile # (09...)',
                              counterText: '',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: refNumCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'GCash Reference # *',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final picked = await picker.pickImage(
                          source: ImageSource.gallery,
                          imageQuality: 85,
                        );
                        if (picked != null) {
                          final len = await picked.length();
                          if (len > 5 * 1024 * 1024) {
                            setModalState(() {
                              modalError =
                                  'Receipt screenshot must not exceed 5MB.';
                            });
                            return;
                          }
                          setModalState(() {
                            receiptFile = picked;
                            modalError = null;
                          });
                        }
                      },
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: Text(
                        receiptFile != null
                            ? 'Receipt: ${receiptFile!.name}'
                            : 'Upload GCash Transfer Screenshot (Max 5MB)*',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (receiptFile != null) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(receiptFile!.path),
                          height: 90,
                          fit: BoxFit.cover,
                        ),
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
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isSubmittingTopup
                            ? null
                            : () async {
                                sanitizePhone(senderPhoneCtrl.text);
                                final sName = senderNameCtrl.text.trim();
                                final sPhone = senderPhoneCtrl.text.trim();
                                final rNum =
                                    refNumCtrl.text.trim().toUpperCase();

                                if (sName.length < 2) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter the GCash sender account name.';
                                  });
                                  return;
                                }
                                if (rNum.length < 4) {
                                  setModalState(() {
                                    modalError =
                                        'Please enter the unique GCash reference number (4+ chars).';
                                  });
                                  return;
                                }
                                if (receiptFile == null) {
                                  setModalState(() {
                                    modalError =
                                        'Please upload your GCash receipt screenshot.';
                                  });
                                  return;
                                }

                                setModalState(() {
                                  modalError = null;
                                  _isSubmittingTopup = true;
                                });

                                try {
                                  final req = http.MultipartRequest(
                                    'POST',
                                    Uri.parse('$_domain/api/v1/wallet/topup'),
                                  );
                                  req.headers['Authorization'] =
                                      'Bearer ${widget.token}';
                                  req.headers['Accept'] = 'application/json';
                                  req.fields['sender_account_name'] = sName;
                                  if (sPhone.isNotEmpty) {
                                    req.fields['sender_account_number'] =
                                        sPhone;
                                  }
                                  req.fields['reference_number'] = rNum;
                                  req.files.add(
                                    await http.MultipartFile.fromPath(
                                      'screenshot',
                                      receiptFile!.path,
                                    ),
                                  );

                                  final streamed = await req
                                      .send()
                                      .timeout(ApiConfig.requestTimeout);
                                  final response =
                                      await http.Response.fromStream(streamed);
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
                                          'Top-up receipt submitted for Admin verification!',
                                      isError: false,
                                    );
                                    _loadAllData(silent: true);
                                  } else {
                                    String err = data is Map
                                        ? (data['message']?.toString() ??
                                            'Failed to submit top-up.')
                                        : 'Failed to submit top-up.';
                                    if (data is Map &&
                                        data['errors'] is Map &&
                                        (data['errors'] as Map).isNotEmpty) {
                                      final first =
                                          (data['errors'] as Map).values.first;
                                      if (first is List && first.isNotEmpty) {
                                        err = first.first.toString();
                                      }
                                    }
                                    setModalState(() => modalError = err);
                                  }
                                } catch (_) {
                                  setModalState(() {
                                    modalError =
                                        'Network error occurred while uploading.';
                                  });
                                } finally {
                                  if (modalContext.mounted) {
                                    setModalState(
                                        () => _isSubmittingTopup = false);
                                  }
                                }
                              },
                        child: _isSubmittingTopup
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Submit Top-Up Receipt'),
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

  @override
  Widget build(BuildContext context) {
    final rewardState = ref.watch(rewardSummaryProvider);
    final int liveCoins = rewardState.isLoaded
        ? rewardState.coinsBalance
        : (int.tryParse(_walletInfo['coins_balance']?.toString() ?? '0') ?? 0);
    final double livePesoEq = liveCoins * 0.10;
    final int liveSpins = rewardState.isLoaded
        ? rewardState.spinTickets
        : (int.tryParse(_walletInfo['spin_tickets']?.toString() ?? '0') ?? 0);

    return Scaffold(
      backgroundColor: StorkTheme.surfaceSubtle,
      appBar: AppBar(
        title: const Text('My Coins & Storkia E-Wallet'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: StorkTheme.primary,
          labelColor: StorkTheme.primary,
          unselectedLabelColor: StorkTheme.textMuted,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          tabs: const [
            Tab(text: 'Storkia Coins & Rewards'),
            Tab(text: 'Real-Money E-Wallet'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: StorkTheme.primary),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCoinsAndRewardsTab(
                  liveCoins: liveCoins,
                  livePesoEq: livePesoEq,
                  liveSpins: liveSpins,
                  chestCanOpen: rewardState.isLoaded
                      ? rewardState.canOpenChest
                      : (_chestInfo['can_open'] == true),
                  chestCooldownSec: rewardState.isLoaded
                      ? rewardState.chestCooldownSec
                      : (int.tryParse(
                              _chestInfo['cooldown_sec']?.toString() ?? '0') ??
                          0),
                ),
                _buildEwalletTab(),
              ],
            ),
    );
  }

  Widget _buildCoinsAndRewardsTab({
    required int liveCoins,
    required double livePesoEq,
    required int liveSpins,
    required bool chestCanOpen,
    required int chestCooldownSec,
  }) {
    return RefreshIndicator(
      color: StorkTheme.primary,
      onRefresh: () => _loadAllData(),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [StorkTheme.primaryDark, StorkTheme.primary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'CHECKOUT RATE: 10 COINS = ₱1.00',
                        style: TextStyle(
                          color: StorkTheme.brandLight,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$liveSpins Spin Ticket(s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.end,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      '$liveCoins Coins',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '(≈ ₱${_formatMoney(livePesoEq)} Checkout Discount)',
                        style: const TextStyle(
                          color: StorkTheme.brandLight,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Redeem any whole-number amount ≥ 10 coins at checkout (up to 25% of net merchandise subtotal), or exchange coins below for vouchers.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: StorkTheme.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: StorkTheme.borderSubtle),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Image.asset(
                    chestCanOpen
                        ? 'assets/chest-frame-1.png'
                        : 'assets/chest-for-reward-stage-1.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.redeem_rounded,
                      size: 42,
                      color: StorkTheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Treasure Chest (3-Tap Unlock)',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: StorkTheme.primaryDark,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chestCanOpen
                            ? 'Ready to unlock! Tap 3 times to win Stage 1, 2, or 3 Jackpot Coins.'
                            : 'Next chest unlocks in ${_formatDuration(chestCooldownSec)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: StorkTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => DailyTreasureChestDialog(
                        baseUrl: _domain,
                        token: widget.token,
                      ),
                    ).then((_) => _loadAllData(silent: true));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        chestCanOpen ? StorkTheme.primary : StorkTheme.darkGrey,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  child: Text(
                    chestCanOpen ? 'Open Chest' : 'View Timer',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _buildSpinWheelSection(liveSpins),
          const SizedBox(height: 14),
          _buildRedeemVoucherCatalogSection(liveCoins),
          const SizedBox(height: 14),
          _buildRewardTransactionsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSpinWheelSection(int liveSpins) {
    final List<JsonMap> segments = _wheelSegments.isNotEmpty
        ? _wheelSegments
        : [
            {'label': '5 Coins', 'color': '#CF4173', 'text_color': '#FFFFFF'},
            {
              'label': 'Free 3 Spins',
              'color': '#5D3140',
              'text_color': '#F6D8BD'
            },
            {'label': '15 Coins', 'color': '#F39399', 'text_color': '#5D3140'},
            {'label': '₱25 Ship', 'color': '#F6D8BD', 'text_color': '#5D3140'},
            {'label': '30 Coins', 'color': '#CF4173', 'text_color': '#FFFFFF'},
            {
              'label': '₱40 Voucher',
              'color': '#5D3140',
              'text_color': '#FFFFFF'
            },
            {'label': '60 Coins', 'color': '#F39399', 'text_color': '#5D3140'},
            {'label': '10% Off', 'color': '#F6D8BD', 'text_color': '#5D3140'},
          ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: StorkTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: StorkTheme.borderSubtle),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '24-Hour Daily Login Spin Wheel',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '+1 Spin Attempt automatically stacks every 24h login',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: StorkTheme.brandLight.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$liveSpins Spin(s)',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: StorkTheme.primaryDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 250,
            height: 250,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.rotate(
                  angle: _wheelRotationRadians,
                  child: CustomPaint(
                    size: const Size(240, 240),
                    painter: _SpinWheelPainter(segments: segments),
                  ),
                ),
                const Positioned(
                  top: 0,
                  child: Icon(
                    Icons.arrow_drop_down_circle_rounded,
                    size: 34,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                GestureDetector(
                  onTap: (_isSpinning || liveSpins <= 0) ? null : _spinWheel,
                  child: Container(
                    width: 66,
                    height: 66,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: liveSpins > 0
                            ? const [StorkTheme.primaryDark, StorkTheme.primary]
                            : const [Colors.grey, Colors.blueGrey],
                      ),
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: _isSpinning
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            liveSpins > 0 ? 'SPIN' : '0 SPINS',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isSpinning || liveSpins <= 0) ? null : _spinWheel,
              child: Text(
                liveSpins > 0
                    ? 'Spin the Wheel ($liveSpins Attempt${liveSpins == 1 ? '' : 's'} Left)'
                    : 'Next Daily Spin Unlocks Soon',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRedeemVoucherCatalogSection(int liveCoins) {
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
          const Text(
            'Redeem Storkia Coins for Vouchers',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Exchange your coins for Platform or Free Shipping vouchers.',
            style: TextStyle(fontSize: 12, color: StorkTheme.textMuted),
          ),
          const SizedBox(height: 12),
          for (final item in _redeemCatalog) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StorkTheme.surfaceSubtle,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: StorkTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: StorkTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${item['coins_cost'] ?? 0}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: StorkTheme.primary,
                          ),
                        ),
                        const Text(
                          'COINS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.primaryDark,
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
                          item['title']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: StorkTheme.textMain,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item['description']?.toString() ?? '',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: StorkTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: (liveCoins >=
                                (int.tryParse(item['coins_cost']?.toString() ??
                                        '0') ??
                                    0) &&
                            _redeemingKey == null)
                        ? () => _redeemVoucherWithCoins(item)
                        : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 34),
                    ),
                    child: _redeemingKey == item['key']?.toString()
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Redeem',
                            style: TextStyle(fontSize: 11.5),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRewardTransactionsSection() {
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
          const Text(
            'Coins & Spins Ledger',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: StorkTheme.primaryDark,
            ),
          ),
          const SizedBox(height: 10),
          if (_rewardTransactions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No coin or spin transactions recorded yet.',
                style: TextStyle(fontSize: 12.5, color: StorkTheme.textMuted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _rewardTransactions.length,
              separatorBuilder: (_, __) => const Divider(height: 16),
              itemBuilder: (context, index) {
                final tx = _rewardTransactions[index];
                final int coinsDelta =
                    int.tryParse(tx['coins_delta']?.toString() ?? '0') ?? 0;
                final int spinsDelta =
                    int.tryParse(tx['spins_delta']?.toString() ?? '0') ?? 0;
                final bool isPositive = coinsDelta > 0 || spinsDelta > 0;

                return Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx['description']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: StorkTheme.textMain,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tx['reference_code']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: StorkTheme.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      coinsDelta != 0
                          ? '${coinsDelta > 0 ? '+' : ''}$coinsDelta Coins'
                          : '${spinsDelta > 0 ? '+' : ''}$spinsDelta Spin(s)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color:
                            isPositive ? StorkTheme.success : StorkTheme.danger,
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

  Widget _buildEwalletTab() {
    final double available = double.tryParse(
            _buyerEwallet['available_balance']?.toString() ?? '0') ??
        0.0;
    final double totalEarned =
        double.tryParse(_buyerEwallet['total_earned']?.toString() ?? '0') ??
            0.0;
    final double totalSpent =
        double.tryParse(_buyerEwallet['total_withdrawn']?.toString() ?? '0') ??
            0.0;

    return RefreshIndicator(
      color: StorkTheme.primary,
      onRefresh: () => _loadAllData(),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E293B), Color(0xFF5D3140)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'STORKIA BUYER E-WALLET (REAL-MONEY PESO BALANCE)',
                  style: TextStyle(
                    color: StorkTheme.brandLight,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '₱${_formatMoney(available)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Total Credited: ₱${_formatMoney(totalEarned)}  •  Used at Checkout: ₱${_formatMoney(totalSpent)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openTopUpModal,
                    icon: const Icon(Icons.add_card_rounded, size: 18),
                    label: const Text('Top Up E-Wallet via GCash Screenshot'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: StorkTheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
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
                  'GCash Top-Up Verification History',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                if (_topupSubmissions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No GCash top-up requests submitted yet.',
                      style: TextStyle(
                          fontSize: 12.5, color: StorkTheme.textMuted),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _topupSubmissions.length,
                    separatorBuilder: (_, __) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final t = _topupSubmissions[index];
                      final String status =
                          t['status']?.toString() ?? 'pending_verification';
                      final bool isApproved = status == 'approved';
                      final bool isRejected = status == 'rejected';

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${t['topup_reference'] ?? ''} • GCash Ref #${t['reference_number'] ?? ''}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: StorkTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Sender: ${t['sender_account_name'] ?? ''}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                                if (t['admin_remarks'] != null &&
                                    t['admin_remarks']
                                        .toString()
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Admin Note: ${t['admin_remarks']}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isRejected
                                          ? StorkTheme.danger
                                          : StorkTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isApproved
                                      ? StorkTheme.success
                                          .withValues(alpha: 0.14)
                                      : (isRejected
                                          ? StorkTheme.danger
                                              .withValues(alpha: 0.14)
                                          : StorkTheme.warning
                                              .withValues(alpha: 0.16)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isApproved
                                      ? '+₱${_formatMoney(t['approved_amount'])}'
                                      : (isRejected ? 'REJECTED' : 'PENDING'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w900,
                                    color: isApproved
                                        ? StorkTheme.success
                                        : (isRejected
                                            ? StorkTheme.danger
                                            : const Color(0xFF92400E)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
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
                  'E-Wallet Transaction Ledger',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: StorkTheme.primaryDark,
                  ),
                ),
                const SizedBox(height: 8),
                if (_walletTransactions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      'No E-Wallet transactions recorded yet.',
                      style: TextStyle(
                          fontSize: 12.5, color: StorkTheme.textMuted),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _walletTransactions.length,
                    separatorBuilder: (_, __) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final tx = _walletTransactions[index];
                      final double amt =
                          double.tryParse(tx['amount']?.toString() ?? '0') ??
                              0.0;
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tx['description']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: StorkTheme.textMain,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  tx['transaction_reference']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: StorkTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${amt >= 0 ? '+' : '-'}₱${_formatMoney(amt.abs())}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: amt >= 0
                                  ? StorkTheme.success
                                  : StorkTheme.danger,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SpinWheelPainter extends CustomPainter {
  final List<JsonMap> segments;

  _SpinWheelPainter({required this.segments});

  Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.isEmpty) return fallback;
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      final val = int.tryParse('FF$clean', radix: 16);
      if (val != null) return Color(val);
    }
    return fallback;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final count = segments.isNotEmpty ? segments.length : 8;
    final sweep = (2 * math.pi) / count;

    final borderPaint = Paint()
      ..color = const Color(0xFF5D3140)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    for (int i = 0; i < count; i++) {
      final seg = segments[i];
      final bgColor = _parseHexColor(
        seg['color']?.toString(),
        i.isEven ? StorkTheme.primary : StorkTheme.brandLight,
      );
      final txtColor = _parseHexColor(
        seg['text_color']?.toString(),
        Colors.white,
      );

      final startAngle = i * sweep;
      final paint = Paint()
        ..color = bgColor
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        true,
        paint,
      );

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(startAngle + (sweep / 2));

      final textSpan = TextSpan(
        text: seg['label']?.toString() ?? '',
        style: TextStyle(
          color: txtColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
        ),
      );
      final tp = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: radius * 0.58);

      tp.paint(canvas, Offset(radius * 0.34, -tp.height / 2));
      canvas.restore();
    }

    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpinWheelPainter oldDelegate) =>
      oldDelegate.segments != segments;
}
