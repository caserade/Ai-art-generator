import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_game_maker/ai_vision/companion.dart';
import 'package:mobile_game_maker/storage/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    GameDatabase.instance.resetForTest();
    await GameDatabase.instance.init(forceMemory: true);
  });

  test('Kaiju responds with aware help', () async {
    final kaiju = CompanionBrain();
    await kaiju.init();
    kaiju.currentRoute = 'home';
    final reply = await kaiju.respond('who are you');
    expect(reply.text.toLowerCase(), contains('kaiju'));
    expect(reply.text.toLowerCase(), contains('home'));
  });

  test('Kaiju designs a game from a brief', () async {
    final kaiju = CompanionBrain();
    await kaiju.init();
    final reply = await kaiju.respond(
      'design a floaty double-jump gem hunt platformer',
    );
    expect(reply.project, isNotNull);
    expect(reply.project!.map.findSpawn(), isNotNull);
  });
}
