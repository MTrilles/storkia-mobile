import 'package:laravel_echo/laravel_echo.dart';
import 'package:pusher_client_fixed/pusher_client_fixed.dart';
import '../config/api_config.dart';

class WebSocketService {
  static Echo? echo;
  static PusherClient? pusherClient;

  static void init(String token) {
    try {
      PusherOptions options = PusherOptions(
        host: ApiConfig.websocketHost,
        wsPort: ApiConfig.websocketPort,
        wssPort: ApiConfig.websocketPort,
        encrypted: true,
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
        enableLogging: false,
      );

      pusherClient?.connect();

      echo = Echo(
        broadcaster: EchoBroadcasterType.Pusher,
        client: pusherClient,
      );
    } catch (e) {
      // Catch initialization errors so it doesn't break the entire screen's HTTP requests
    }
  }

  static void listenToChat(int userId, Function(dynamic) onMessageReceived) {
    if (echo == null) return;

    try {
      echo!.private('chat.$userId').listen('.MessageSent', (e) {
        onMessageReceived(e);
      });
    } catch (e) {
      // Prevent listener crash from halting execution
    }
  }

  static void disconnect() {
    try {
      pusherClient?.disconnect();
      echo?.disconnect();
    } catch (e) {
      // Ignore disconnect errors
    }
  }
}
