import 'package:flutter_test/flutter_test.dart';

import 'package:gemma_local_app/src/app/gemma_local_app.dart';

void main() {
  testWidgets('Gemma Local smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GemmaLocalApp());

    expect(find.text('Gemma Local'), findsWidgets);
    expect(find.text('Gemma-4-E2B-it'), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('Prompt Lab'), findsOneWidget);
    expect(find.text('Skills'), findsOneWidget);
    expect(find.text('图片理解'), findsOneWidget);
    expect(find.text('声音理解'), findsOneWidget);
  });
}
