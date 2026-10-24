import 'package:laravel_echo/laravel_echo.dart';
import 'package:pusher_client_fixed/pusher_client_fixed.dart';
import '../config/api_config.dart';

class WebSocketService {
  static Echo? echo;
  static PusherClient? pusherClient;

  static void init(String token) {
    PusherOptions options = PusherOptions(
      host: ApiConfig.websocketHost,
      wsPort: ApiConfig.websocketPort,
      wssPort: ApiConfig.websocketPort, // Added WSS Port binding
      encrypted: true, // MUST BE TRUE for an HTTPS backend (dev.storkia.shop)
      auth: PusherAuth(
        '${ApiConfig.baseUrl}/broadcasting/auth',
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      ),
    );

    pusherClient = PusherClient(
      ApiConfig.pusherKey,
      options,
      autoConnect: true,
      enableLogging: true, // Will help you verify successful connection in logs
    );

    echo = Echo(
      broadcaster: EchoBroadcasterType.Pusher,
      client: pusherClient,
    );
  }

  static void listenToChat(int userId, Function(dynamic) onMessageReceived) {
    if (echo == null) return;

    echo!.private('chat.$userId').listen('.MessageSent', (e) {
      onMessageReceived(e);
    });
  }

  static void disconnect() {
    pusherClient?.disconnect();
    echo?.disconnect();
  }
}
