import 'package:flutter_test/flutter_test.dart';

import 'package:gemma_local_app/src/app/gemma_local_app.dart';

void main() {
  testWidgets('galleryFlutter smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GemmaLocalApp());
    await tester.pump();

    expect(find.text('galleryFlutter'), findsWidgets);
    expect(find.text('Gemma-4-E2B-it · Local AI'), findsOneWidget);
    expect(find.text('文字'), findsWidgets);
    expect(find.text('Prompt Lab'), findsWidgets);
    expect(find.text('Skills'), findsWidgets);
    expect(find.text('图片'), findsWidgets);
    expect(find.text('语音'), findsWidgets);
    expect(find.textContaining('你好，我是 galleryFlutter'), findsOneWidget);
  });
}
