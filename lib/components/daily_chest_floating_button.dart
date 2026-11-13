import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../config/app_theme.dart';
import '../providers/global_counters_provider.dart';

typedef JsonMap = Map<String, dynamic>;

class DailyChestFloatingButton extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;
  final VoidCallback? onOpenRewardsHub;

  const DailyChestFloatingButton({
    super.key,
    required this.baseUrl,
    required this.token,
    this.onOpenRewardsHub,
  });

  @override
  ConsumerState<DailyChestFloatingButton> createState() =>
      _DailyChestFloatingButtonState();
}

class _DailyChestFloatingButtonState
    extends ConsumerState<DailyChestFloatingButton> {
  Timer? _countdownTimer;
  int _localCooldownSec = 0;

  @override
  void initState() {
    super.initState();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_localCooldownSec > 0 && mounted) {
        setState(() => _localCooldownSec--);
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  String _formatShortTimer(int sec) {
    if (sec <= 0) return 'OPEN!';
    final h = (sec ~/ 3600).toString().padLeft(2, '0');
    final m = ((sec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final rewardState = ref.watch(rewardSummaryProvider);
    if (rewardState.chestCooldownSec > 0 &&
        (_localCooldownSec == 0 ||
            (rewardState.chestCooldownSec - _localCooldownSec).abs() > 8)) {
      _localCooldownSec = rewardState.chestCooldownSec;
    } else if (rewardState.canOpenChest) {
      _localCooldownSec = 0;
    }

    final bool canOpen = rewardState.canOpenChest || _localCooldownSec <= 0;

    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => DailyTreasureChestDialog(
            baseUrl: widget.baseUrl,
            token: widget.token,
            onOpenRewardsHub: widget.onOpenRewardsHub,
          ),
        );
      },
      child: Container(
        width: 74,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        decoration: BoxDecoration(
          gradient: canOpen
              ? StorkTheme.brandGradient
              : const LinearGradient(
                  colors: [Color(0xFF292524), Color(0xFF44403C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: canOpen
                ? StorkTheme.brandLight
                : Colors.white.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: StorkTheme.primaryDark.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: Image.asset(
                'assets/chest-frame-1.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.redeem_rounded,
                  color: StorkTheme.brandLight,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: canOpen
                    ? Colors.amber.shade400
                    : Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                canOpen ? 'OPEN!' : _formatShortTimer(_localCooldownSec),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                  color: canOpen ? StorkTheme.primaryDark : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DailyTreasureChestDialog extends ConsumerStatefulWidget {
  final String baseUrl;
  final String token;
  final VoidCallback? onOpenRewardsHub;

  const DailyTreasureChestDialog({
    super.key,
    required this.baseUrl,
    required this.token,
    this.onOpenRewardsHub,
  });

  @override
  ConsumerState<DailyTreasureChestDialog> createState() =>
      _DailyTreasureChestDialogState();
}

class _DailyTreasureChestDialogState
    extends ConsumerState<DailyTreasureChestDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  Timer? _cooldownTimer;

  bool _isLoadingStatus = true;
  bool _canOpen = false;
  bool _isOpeningApi = false;
  int _cooldownSec = 0;
  int _tapCount = 0;

  bool _rewardUnlocked = false;
  int _wonStage = 1;
  String _wonStageLabel = '';
  int _wonCoins = 0;
  String _wonMessage = '';

  String get _domain => ApiConfig.resolveBaseDomain(widget.baseUrl);

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fetchChestStatus();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_cooldownSec > 0 && mounted) {
        setState(() {
          _cooldownSec--;
          if (_cooldownSec <= 0) {
            _canOpen = true;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _fetchChestStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_domain/api/v1/rewards/chest'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      if (response.statusCode == 200) {
        final body = json.decode(response.body);
        final d = body is Map ? (body['data'] ?? body) : null;
        if (d is Map) {
          final chest = d['chest'] is Map
              ? JsonMap.from(d['chest'] as Map)
              : JsonMap.from(d);
          final int sec =
              int.tryParse(chest['cooldown_sec']?.toString() ?? '0') ?? 0;
          final bool open = chest['can_open'] == true || sec <= 0;
          setState(() {
            _canOpen = open;
            _cooldownSec = sec;
            _isLoadingStatus = false;
          });
          return;
        }
      }
    } catch (_) {}

    if (mounted) {
      final summary = ref.read(rewardSummaryProvider);
      setState(() {
        _canOpen = summary.canOpenChest;
        _cooldownSec = summary.chestCooldownSec;
        _isLoadingStatus = false;
      });
    }
  }

  Future<void> _onTapChest() async {
    if (!_canOpen || _isOpeningApi || _rewardUnlocked) return;

    _shakeController.forward(from: 0.0);
    final nextTap = _tapCount + 1;
    setState(() => _tapCount = nextTap);

    if (nextTap < 3) return;

    setState(() => _isOpeningApi = true);
    try {
      final response = await http.post(
        Uri.parse('$_domain/api/v1/rewards/chest/open'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Accept': 'application/json',
        },
      ).timeout(ApiConfig.requestTimeout);

      if (!mounted) return;
      final body = json.decode(response.body);
      final JsonMap data = (body is Map && body['data'] is Map)
          ? JsonMap.from(body['data'] as Map)
          : (body is Map ? JsonMap.from(body) : <String, dynamic>{});

      if (response.statusCode == 200 &&
          (body['success'] == true || data['coins_won'] != null)) {
        final int stage =
            (int.tryParse(data['stage']?.toString() ?? '1') ?? 1).clamp(1, 3);
        final int coinsWon =
            int.tryParse(data['coins_won']?.toString() ?? '10') ?? 10;
        final int newBalance =
            int.tryParse(data['coins_balance']?.toString() ?? '0') ?? 0;
        final int newCooldown =
            int.tryParse(data['cooldown_sec']?.toString() ?? '86400') ?? 86400;

        ref.read(rewardSummaryProvider.notifier).applyChestOpened(
              coinsBalance: newBalance,
              cooldownSec: newCooldown,
            );

        setState(() {
          _rewardUnlocked = true;
          _canOpen = false;
          _cooldownSec = newCooldown;
          _wonStage = stage;
          _wonStageLabel =
              data['stage_label']?.toString() ?? 'Stage $stage Treasure';
          _wonCoins = coinsWon;
          _wonMessage = data['message']?.toString() ??
              'Unlocked +$coinsWon Storkia Coins!';
          _isOpeningApi = false;
        });
      } else {
        setState(() {
          _tapCount = 0;
          _isOpeningApi = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message']?.toString() ??
                  'Your Daily Chest is cooling down.',
            ),
            backgroundColor: StorkTheme.danger,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tapCount = 0;
          _isOpeningApi = false;
        });
      }
    }
  }

  String _currentChestAsset() {
    if (_rewardUnlocked) {
      return 'assets/chest-for-reward-stage-$_wonStage.png';
    }
    if (_tapCount <= 0) return 'assets/chest-frame-1.png';
    if (_tapCount == 1) return 'assets/chest-frame-2.png';
    return 'assets/chest-frame-3.png';
  }

  String _formatCooldown(int totalSec) {
    if (totalSec <= 0) return 'Ready to Open!';
    final h = (totalSec ~/ 3600).toString().padLeft(2, '0');
    final m = ((totalSec % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: StorkTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: _isLoadingStatus
            ? const SizedBox(
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(color: StorkTheme.primary),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: StorkTheme.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          _rewardUnlocked
                              ? 'STAGE $_wonStage REWARD UNLOCKED!'
                              : 'DAILY TREASURE CHEST',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _onTapChest,
                    child: AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final double offset = (_shakeController.value * 12) *
                            ((_shakeController.value * 10).round().isEven
                                ? 1
                                : -1) *
                            (1 - _shakeController.value);
                        return Transform.translate(
                          offset: Offset(offset, 0),
                          child: child,
                        );
                      },
                      child: Container(
                        width: 156,
                        height: 156,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: StorkTheme.brandLight.withValues(alpha: 0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Image.asset(
                          _currentChestAsset(),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.redeem_rounded,
                            size: 88,
                            color: StorkTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_rewardUnlocked) ...[
                    Text(
                      '+$_wonCoins Storkia Coins!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: StorkTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _wonStageLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _wonMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: StorkTheme.textMuted,
                      ),
                    ),
                  ] else if (_canOpen) ...[
                    Text(
                      _isOpeningApi
                          ? 'Unlocking Your Treasure...'
                          : 'Tap Chest ${3 - _tapCount} More Time${(3 - _tapCount) == 1 ? '' : 's'} to Open!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int idx = 0; idx < 3; idx++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 30,
                            height: 8,
                            decoration: BoxDecoration(
                              gradient: idx < _tapCount
                                  ? StorkTheme.brandGradient
                                  : null,
                              color: idx < _tapCount
                                  ? null
                                  : StorkTheme.borderSubtle,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                      ],
                    ),
                  ] else ...[
                    const Text(
                      'Daily Chest Cooling Down',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Next chest unlocks in ${_formatCooldown(_cooldownSec)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: StorkTheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      if (widget.onOpenRewardsHub != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onOpenRewardsHub!();
                            },
                            child: const Text('Rewards Hub'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: StorkTheme.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: (_canOpen && !_rewardUnlocked)
                                ? _onTapChest
                                : () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: Text(
                              (_canOpen && !_rewardUnlocked)
                                  ? 'Tap Chest ($_tapCount/3)'
                                  : 'Done',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
