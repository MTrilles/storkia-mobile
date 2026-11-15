import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'api_service.dart';

class BuyerRealtimeEvent {
  final String event;
  final String channel;
  final String scope;
  final String action;
  final JsonMap data;

  const BuyerRealtimeEvent({
    required this.event,
    required this.channel,
    required this.scope,
    required this.action,
    required this.data,
  });
}

typedef BuyerRealtimeEventListener = void Function(BuyerRealtimeEvent event);
typedef ChatMessageEventCallback = void Function(dynamic payload);

class WebSocketService {
  WebSocketService._();

  static const String defaultReverbAppKey = String.fromEnvironment(
    'REVERB_APP_KEY',
    defaultValue: 'bn93mdlba1frvyhfe5gf',
  );

  static const int defaultReverbPort = int.fromEnvironment(
    'REVERB_PORT',
    defaultValue: 0,
  );

  static const String defaultReverbScheme = String.fromEnvironment(
    'REVERB_SCHEME',
    defaultValue: '',
  );

  static int? _overrideReverbPort;
  static String _overrideReverbAppKey = '';

  static WebSocket? _socket;
  static StreamSubscription<dynamic>? _socketSub;
  static Timer? _pingTimer;
  static Timer? _reconnectTimer;

  static String? _token;
  static int? _userId;
  static String? _socketId;
  static bool _isConnecting = false;
  static bool _isConnected = false;
  static bool _manuallyStopped = false;
  static int _reconnectAttempts = 0;

  static final Set<String> _desiredPrivateChannels = <String>{};
  static final Set<String> _desiredPublicChannels = <String>{'marketplace'};
  static final Set<String> _subscribedChannels = <String>{};

  static final List<BuyerRealtimeEventListener> _listeners =
      <BuyerRealtimeEventListener>[];
  static final List<ChatMessageEventCallback> _chatCallbacks =
      <ChatMessageEventCallback>[];

  static bool get isConnected => _isConnected;
  static String? get socketId => _socketId;

  static void setReverbPortOverride(int port) {
    if (port > 0) {
      _overrideReverbPort = port;
    }
  }

  static void setReverbAppKeyOverride(String appKey) {
    if (appKey.trim().isNotEmpty) {
      _overrideReverbAppKey = appKey.trim();
    }
  }

  static bool _isLocalHost(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' ||
        h == '127.0.0.1' ||
        h == '10.0.2.2' ||
        h.startsWith('192.168.') ||
        h.startsWith('10.') ||
        h.endsWith('.local');
  }

  static String get resolvedReverbWebSocketUrl {
    final baseUri = Uri.tryParse(ApiConfig.baseUrl);
    final rawHost = baseUri?.host.trim() ?? '';
    final host =
        (rawHost.isEmpty || rawHost == '0.0.0.0') ? '127.0.0.1' : rawHost;

    String scheme;
    final explicitScheme = defaultReverbScheme.trim().toLowerCase();
    if (explicitScheme == 'wss' || explicitScheme == 'https') {
      scheme = 'wss';
    } else if (explicitScheme == 'ws' || explicitScheme == 'http') {
      scheme = 'ws';
    } else {
      scheme = (baseUri?.scheme.toLowerCase() == 'https') ? 'wss' : 'ws';
    }

    final int effectivePort = _overrideReverbPort ??
        (defaultReverbPort > 0
            ? defaultReverbPort
            : (_isLocalHost(host) ? 8080 : (scheme == 'wss' ? 443 : 80)));

    final appKey = _overrideReverbAppKey.isNotEmpty
        ? _overrideReverbAppKey
        : (defaultReverbAppKey.isNotEmpty
            ? defaultReverbAppKey
            : 'bn93mdlba1frvyhfe5gf');

    final encodedKey = Uri.encodeComponent(appKey);
    final includePort = !((scheme == 'wss' && effectivePort == 443) ||
        (scheme == 'ws' && effectivePort == 80));
    final portSegment = includePort ? ':$effectivePort' : '';

    return '$scheme://$host$portSegment/app/$encodedKey?protocol=7&client=flutter-dart&version=1.0.0&flash=false';
  }

  static void addListener(BuyerRealtimeEventListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(BuyerRealtimeEventListener listener) {
    _listeners.remove(listener);
  }

  static void removeChatListener(ChatMessageEventCallback callback) {
    _chatCallbacks.remove(callback);
  }

  static Future<void> init(String token, {int? userId}) async {
    final cleanToken = token.trim();
    if (cleanToken.isEmpty) return;

    _manuallyStopped = false;
    _token = cleanToken;

    int? resolvedUserId = userId;
    if (resolvedUserId == null || resolvedUserId <= 0) {
      resolvedUserId = await _resolveSavedUserId();
    }

    if (resolvedUserId != null && resolvedUserId > 0) {
      if (_userId != null && _userId != resolvedUserId) {
        _desiredPrivateChannels.remove('private-user.$_userId');
        _desiredPrivateChannels.remove('private-chat.$_userId');
        _desiredPrivateChannels.remove('private-cart.$_userId');
        _desiredPrivateChannels.remove('private-support.user.$_userId');
        await _closeCurrentSocket();
      }
      _userId = resolvedUserId;
      _desiredPrivateChannels.add('private-user.$resolvedUserId');
      _desiredPrivateChannels.add('private-chat.$resolvedUserId');
      _desiredPrivateChannels.add('private-cart.$resolvedUserId');
      _desiredPrivateChannels.add('private-support.user.$resolvedUserId');
    }

    if (_isConnected && _socket != null) {
      await _subscribePendingChannels();
      return;
    }

    if (_isConnecting) return;
    await _establishConnection();
  }

  static void listenToChat(
      int userId, ChatMessageEventCallback onMessageReceived) {
    if (!_chatCallbacks.contains(onMessageReceived)) {
      _chatCallbacks.add(onMessageReceived);
    }
    if (userId > 0) {
      _userId = userId;
      _desiredPrivateChannels.add('private-user.$userId');
      _desiredPrivateChannels.add('private-chat.$userId');
      _desiredPrivateChannels.add('private-cart.$userId');
      _desiredPrivateChannels.add('private-support.user.$userId');
      if (_isConnected && _socketId != null) {
        _subscribePendingChannels();
      } else if (!_isConnecting && _token != null && _token!.isNotEmpty) {
        _establishConnection();
      }
    }
  }

  static Future<void> subscribeOrderChannel(int sellerOrderId) async {
    if (sellerOrderId <= 0) return;
    final channelName = 'private-order.$sellerOrderId';
    _desiredPrivateChannels.add(channelName);
    if (_isConnected && _socketId != null) {
      await _authorizeAndSubscribePrivateChannel(channelName);
    }
  }

  static void unsubscribeOrderChannel(int sellerOrderId) {
    if (sellerOrderId <= 0) return;
    final channelName = 'private-order.$sellerOrderId';
    _desiredPrivateChannels.remove(channelName);
    _subscribedChannels.remove(channelName);
    _sendFrame(<String, dynamic>{
      'event': 'pusher:unsubscribe',
      'data': <String, dynamic>{'channel': channelName},
    });
  }

  static Future<void> subscribeShipmentChannel(int shipmentId) async {
    if (shipmentId <= 0) return;
    final channelName = 'private-shipment.$shipmentId';
    _desiredPrivateChannels.add(channelName);
    if (_isConnected && _socketId != null) {
      await _authorizeAndSubscribePrivateChannel(channelName);
    }
  }

  static void unsubscribeShipmentChannel(int shipmentId) {
    if (shipmentId <= 0) return;
    final channelName = 'private-shipment.$shipmentId';
    _desiredPrivateChannels.remove(channelName);
    _subscribedChannels.remove(channelName);
    _sendFrame(<String, dynamic>{
      'event': 'pusher:unsubscribe',
      'data': <String, dynamic>{'channel': channelName},
    });
  }

  static Future<int?> _resolveSavedUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('storkia_auth_user');
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return int.tryParse(decoded['id']?.toString() ?? '');
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _establishConnection() async {
    if (_manuallyStopped || _isConnecting) return;
    _isConnecting = true;
    _reconnectTimer?.cancel();

    try {
      final ws = await WebSocket.connect(
        resolvedReverbWebSocketUrl,
      ).timeout(const Duration(seconds: 10));

      _socket = ws;
      _isConnecting = false;
      _reconnectAttempts = 0;

      await _socketSub?.cancel();
      _socketSub = ws.listen(
        _onMessageReceived,
        onDone: _handleSocketClosed,
        onError: (_) => _handleSocketClosed(),
        cancelOnError: true,
      );
    } catch (_) {
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  static void _onMessageReceived(dynamic rawMessage) {
    if (rawMessage is! String || rawMessage.trim().isEmpty) return;

    JsonMap envelope;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map) return;
      envelope = JsonMap.from(decoded);
    } catch (_) {
      return;
    }

    final eventName = (envelope['event'] ?? '').toString();
    final channelName = (envelope['channel'] ?? '').toString();
    final rawData = envelope['data'];

    JsonMap dataMap = <String, dynamic>{};
    if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(rawData);
        if (parsed is Map) {
          dataMap = JsonMap.from(parsed);
        }
      } catch (_) {}
    } else if (rawData is Map) {
      dataMap = JsonMap.from(rawData);
    }

    if (eventName == 'pusher:connection_established') {
      _socketId = dataMap['socket_id']?.toString();
      ApiService.socketId = _socketId;
      _isConnected = true;
      _subscribedChannels.clear();
      final activityTimeout =
          (dataMap['activity_timeout'] as num?)?.toInt() ?? 30;
      _startPingHeartbeat(activityTimeout);
      _subscribePendingChannels();
      return;
    }

    if (eventName == 'pusher:ping') {
      _sendFrame(<String, dynamic>{
        'event': 'pusher:pong',
        'data': <String, dynamic>{},
      });
      return;
    }

    if (eventName.startsWith('pusher_internal:') ||
        eventName.startsWith('pusher:')) {
      return;
    }

    final cleanEventName =
        eventName.startsWith('.') ? eventName.substring(1) : eventName;

    String resolvedScope = (dataMap['scope'] ?? '').toString();
    if (resolvedScope.isEmpty) {
      if (cleanEventName == 'MessageSent' ||
          channelName.startsWith('private-chat.')) {
        resolvedScope = 'chat';
      } else if (cleanEventName == 'SupportMessageSent' ||
          channelName.startsWith('private-support.')) {
        resolvedScope = 'support_chat';
      } else if (cleanEventName == 'CartQuantityUpdated' ||
          cleanEventName == 'CartUpdated' ||
          channelName.startsWith('private-cart.')) {
        resolvedScope = 'cart';
      } else {
        resolvedScope = 'general';
      }
    }

    if (cleanEventName == 'MessageSent' ||
        channelName.startsWith('private-chat.') ||
        resolvedScope == 'chat') {
      final chatSnapshot = List<ChatMessageEventCallback>.from(_chatCallbacks);
      for (final cb in chatSnapshot) {
        try {
          cb(dataMap);
        } catch (_) {}
      }
    }

    final realtimeEvent = BuyerRealtimeEvent(
      event: cleanEventName,
      channel: channelName,
      scope: resolvedScope,
      action: (dataMap['action'] ?? cleanEventName).toString(),
      data: dataMap,
    );

    final snapshot = List<BuyerRealtimeEventListener>.from(_listeners);
    for (final listener in snapshot) {
      try {
        listener(realtimeEvent);
      } catch (_) {}
    }
  }

  static Future<void> _subscribePendingChannels() async {
    if (!_isConnected || _socketId == null) return;

    for (final publicChannel in _desiredPublicChannels) {
      if (!_subscribedChannels.contains(publicChannel)) {
        _sendFrame(<String, dynamic>{
          'event': 'pusher:subscribe',
          'data': <String, dynamic>{'channel': publicChannel},
        });
        _subscribedChannels.add(publicChannel);
      }
    }

    final pendingPrivate = List<String>.from(_desiredPrivateChannels);
    for (final channel in pendingPrivate) {
      if (!_subscribedChannels.contains(channel)) {
        await _authorizeAndSubscribePrivateChannel(channel);
      }
    }
  }

  static Future<void> _authorizeAndSubscribePrivateChannel(
    String channelName,
  ) async {
    if (!_isConnected || _socketId == null || _socketId!.isEmpty) return;
    if (_subscribedChannels.contains(channelName)) return;

    final token = _token;
    if (token == null || token.isEmpty) return;

    try {
      final response = await ApiService.httpClient
          .post(
            Uri.parse('${ApiConfig.baseUrl}/broadcasting/auth'),
            headers: ApiService.buildHeaders(token, isJson: true),
            body: jsonEncode(<String, dynamic>{
              'socket_id': _socketId,
              'channel_name': channelName,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;
      final authSignature = decoded['auth']?.toString();
      if (authSignature == null || authSignature.isEmpty) return;

      final subscribeData = <String, dynamic>{
        'channel': channelName,
        'auth': authSignature,
        if (decoded['channel_data'] != null)
          'channel_data': decoded['channel_data'],
      };

      _sendFrame(<String, dynamic>{
        'event': 'pusher:subscribe',
        'data': subscribeData,
      });

      _subscribedChannels.add(channelName);
    } catch (_) {}
  }

  static void _startPingHeartbeat(int activityTimeoutSeconds) {
    _pingTimer?.cancel();
    final intervalSeconds = (activityTimeoutSeconds > 10)
        ? (activityTimeoutSeconds - 5).clamp(15, 45)
        : 25;

    _pingTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) {
      if (_isConnected && _socket != null) {
        _sendFrame(<String, dynamic>{
          'event': 'pusher:ping',
          'data': <String, dynamic>{},
        });
      }
    });
  }

  static void _sendFrame(JsonMap frame) {
    try {
      _socket?.add(jsonEncode(frame));
    } catch (_) {}
  }

  static void _handleSocketClosed() {
    _isConnected = false;
    _isConnecting = false;
    _socketId = null;
    ApiService.socketId = null;
    _subscribedChannels.clear();
    _pingTimer?.cancel();

    if (!_manuallyStopped && _token != null && _token!.isNotEmpty) {
      _scheduleReconnect();
    }
  }

  static void _scheduleReconnect() {
    if (_manuallyStopped || _token == null || _token!.isEmpty) return;
    _reconnectTimer?.cancel();
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(1, 6);
    final delaySeconds = (2 * _reconnectAttempts).clamp(2, 15);

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_manuallyStopped && _token != null && _token!.isNotEmpty) {
        _establishConnection();
      }
    });
  }

  static Future<void> _closeCurrentSocket() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
    _socketId = null;
    ApiService.socketId = null;
    _isConnected = false;
    _isConnecting = false;
    _subscribedChannels.clear();
  }

  static Future<void> disconnect() async {
    _manuallyStopped = true;
    _token = null;
    _userId = null;
    _desiredPrivateChannels.clear();
    _chatCallbacks.clear();
    await _closeCurrentSocket();
  }
}
