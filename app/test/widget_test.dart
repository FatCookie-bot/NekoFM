import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/app/nekofm_app.dart';

void main() {
  testWidgets('shows the NekoFM shell destinations', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NekoFmApp()));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Library'), findsWidgets);
    expect(find.text('Player'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
