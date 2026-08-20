import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_game_maker/app.dart';
import 'package:mobile_game_maker/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    GameDatabase.instance.resetForTest();
    await GameDatabase.instance.init(forceMemory: true);
    // Skip auto-welcome panel animation loops in tests
    await GameDatabase.instance.setSetting('kaiju_welcomed', '1');
  });

  testWidgets('Home shows Game Maker branding and Kaiju', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GameMakerApp()));
    // Avoid pumpAndSettle — companion FAB pulse is a repeating animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.textContaining('Game Maker'), findsWidgets);
    expect(find.textContaining('Kaiju'), findsWidgets);
    expect(find.text('AI Brain'), findsOneWidget);
    expect(find.text('Art Scanner'), findsOneWidget);
    expect(find.text('Map Parser'), findsOneWidget);
    expect(find.text('Physics AI'), findsOneWidget);
  });
}
