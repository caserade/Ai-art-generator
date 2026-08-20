import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_game_maker/controllers/dual_control_engine.dart';
import 'package:mobile_game_maker/models/game_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('virtual sticks and buttons update ControlState', () async {
    final engine = DualControlEngine()..hapticsEnabled = false;
    await engine.start();

    engine.setLeftStick(0.8, -0.2);
    expect(engine.state.leftX, closeTo(0.8, 0.001));
    expect(engine.state.moveRight, isTrue);

    engine.pressButton(GamepadButton.a, pressed: true);
    expect(engine.state.jump, isTrue);

    engine.pressButton(GamepadButton.a, pressed: false);
    expect(engine.state.jump, isFalse);

    engine.setDpad(left: true);
    expect(engine.state.moveLeft, isTrue);

    await engine.dispose();
  });

  test('button remap resolves aliases', () {
    final remap = ButtonRemapConfig();
    expect(remap.resolve('cross'), GamepadButton.a);
    expect(remap.resolve('TRIANGLE'), GamepadButton.y);
    remap.setBinding('custom_fire', GamepadButton.b);
    expect(remap.resolve('custom_fire'), GamepadButton.b);
  });
}
