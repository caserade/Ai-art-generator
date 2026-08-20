import 'package:flutter/services.dart';
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

  test('keyboard WASD + Space drive move and jump', () async {
    final engine = DualControlEngine()..hapticsEnabled = false;
    await engine.start();

    expect(
      engine.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.keyD,
          logicalKey: LogicalKeyboardKey.keyD,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(engine.state.moveRight, isTrue);

    expect(
      engine.handleKeyEvent(
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.space,
          logicalKey: LogicalKeyboardKey.space,
          timeStamp: Duration.zero,
        ),
      ),
      isTrue,
    );
    expect(engine.state.jump, isTrue);

    engine.handleKeyEvent(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.space,
        logicalKey: LogicalKeyboardKey.space,
        timeStamp: Duration.zero,
      ),
    );
    expect(engine.state.jump, isFalse);

    engine.handleKeyEvent(
      const KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyD,
        logicalKey: LogicalKeyboardKey.keyD,
        timeStamp: Duration.zero,
      ),
    );
    expect(engine.state.moveRight, isFalse);

    await engine.dispose();
  });
}
