import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_game_maker/app.dart';
import 'package:mobile_game_maker/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    GameDatabase.instance.resetForTest();
    await GameDatabase.instance.init(forceMemory: true);
  });

  testWidgets('Home shows Game Maker branding', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GameMakerApp()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Game Maker'), findsWidgets);
    expect(find.textContaining('Mobile Game Maker'), findsOneWidget);
    expect(find.text('AI Brain'), findsOneWidget);
    expect(find.text('Art Scanner'), findsOneWidget);
    expect(find.text('Map Parser'), findsOneWidget);
    expect(find.text('Physics AI'), findsOneWidget);
  });
}
