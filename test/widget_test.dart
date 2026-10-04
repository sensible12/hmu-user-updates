import 'package:flutter_test/flutter_test.dart';

import 'package:hmu/features/app_shell.dart';

void main() {
  testWidgets('app shell renders firebase setup fallback', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp(firebaseReady: false));
    await tester.pump();

    expect(find.text('Firebase setup is missing for this project.'), findsOneWidget);
  });
}
