import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storkia_mobile/main.dart';

void main() {
  testWidgets('Storkia app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: StorkiaMobileApp(),
      ),
    );
    expect(find.byType(StorkiaMobileApp), findsOneWidget);
  });
}
