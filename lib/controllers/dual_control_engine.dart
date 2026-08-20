import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gamepads/gamepads.dart';

import '../models/game_models.dart';
import 'hid_availability_stub.dart'
    if (dart.library.io) 'hid_availability_io.dart';

/// Remappable logical ↔ physical button bindings.
class ButtonRemapConfig {
  ButtonRemapConfig({Map<String, GamepadButton>? bindings})
      : bindings = bindings ?? defaultBindings();

  final Map<String, GamepadButton> bindings;

  static Map<String, GamepadButton> defaultBindings() => {
        'a': GamepadButton.a,
        'b': GamepadButton.b,
        'x': GamepadButton.x,
        'y': GamepadButton.y,
        'dpad_up': GamepadButton.up,
        'dpad_down': GamepadButton.down,
        'dpad_left': GamepadButton.left,
        'dpad_right': GamepadButton.right,
        'start': GamepadButton.start,
        'select': GamepadButton.select,
        // Common HID aliases (Xbox / DualSense / 8BitDo)
        'button_a': GamepadButton.a,
        'button_b': GamepadButton.b,
        'button_x': GamepadButton.x,
        'button_y': GamepadButton.y,
        'cross': GamepadButton.a,
        'circle': GamepadButton.b,
        'square': GamepadButton.x,
        'triangle': GamepadButton.y,
      };

  GamepadButton? resolve(String key) {
    final normalized = key.toLowerCase().replaceAll(' ', '_');
    return bindings[normalized];
  }

  void setBinding(String physicalKey, GamepadButton logical) {
    bindings[physicalKey.toLowerCase()] = logical;
  }

  Map<String, String> toJson() =>
      bindings.map((k, v) => MapEntry(k, v.name));

  factory ButtonRemapConfig.fromJson(Map<String, dynamic> json) {
    final map = <String, GamepadButton>{};
    json.forEach((key, value) {
      map[key] = GamepadButton.values.firstWhere(
        (b) => b.name == value,
        orElse: () => GamepadButton.a,
      );
    });
    return ButtonRemapConfig(bindings: map);
  }
}

/// Merges virtual overlay + native HID gamepad into one [ControlState].
class DualControlEngine {
  DualControlEngine({ButtonRemapConfig? remap})
      : remap = remap ?? ButtonRemapConfig();

  final ButtonRemapConfig remap;
  final ControlState state = ControlState();
  final _controller = StreamController<ControlState>.broadcast();

  StreamSubscription<GamepadEvent>? _padSub;
  List<GamepadController> _pads = [];
  bool hapticsEnabled = true;

  Stream<ControlState> get stream => _controller.stream;

  Future<void> start() async {
    if (kIsWeb || !canUseHidGamepads) {
      return;
    }
    try {
      _pads = await Gamepads.list();
    } catch (_) {
      _pads = [];
    }
    try {
      _padSub = Gamepads.events.listen(_onPadEvent);
    } catch (_) {
      // Desktop may lack HID; keyboard + virtual controls still work.
    }
  }

  List<String> get connectedPadNames =>
      _pads.map((p) => p.name).toList(growable: false);

  void _onPadEvent(GamepadEvent event) {
    final key = event.key.toLowerCase();
    final logical = remap.resolve(key);
    if (logical != null && event.type == KeyType.button) {
      if (event.value > 0.5) {
        state.pressed.add(logical);
        _hapticLight();
      } else {
        state.pressed.remove(logical);
      }
    }

    // Axes (Xbox / DualSense / 8BitDo naming variants)
    if ((key.contains('left') && key.contains('x')) || key == 'axis_0') {
      state.leftX = event.value;
    } else if ((key.contains('left') && key.contains('y')) || key == 'axis_1') {
      state.leftY = event.value;
    } else if ((key.contains('right') && key.contains('x')) || key == 'axis_2') {
      state.rightX = event.value;
    } else if ((key.contains('right') && key.contains('y')) || key == 'axis_3') {
      state.rightY = event.value;
    }

    _emit();
  }

  // —— Keyboard (PC native) ——
  // WASD / arrows move · Space / W / Up jump · J/Z = A · K/X = B · L/C = X · I/V = Y

  bool _keyLeft = false;
  bool _keyRight = false;
  bool _keyUp = false;
  bool _keyDown = false;
  bool _keyJump = false; // Space / J / Z
  bool _virtualStickActive = false;

  /// Returns true when the key was consumed for gameplay.
  bool handleKeyEvent(KeyEvent event) {
    final isDown = event is KeyDownEvent || event is KeyRepeatEvent;
    final isUp = event is KeyUpEvent;
    if (!isDown && !isUp) return false;

    final key = event.logicalKey;
    var handled = false;

    void setFlag(void Function(bool) assign) {
      if (isDown) assign(true);
      if (isUp) assign(false);
      handled = true;
    }

    if (key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.arrowLeft) {
      setFlag((v) => _keyLeft = v);
    } else if (key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.arrowRight) {
      setFlag((v) => _keyRight = v);
    } else if (key == LogicalKeyboardKey.keyW ||
        key == LogicalKeyboardKey.arrowUp) {
      setFlag((v) => _keyUp = v);
    } else if (key == LogicalKeyboardKey.keyS ||
        key == LogicalKeyboardKey.arrowDown) {
      setFlag((v) => _keyDown = v);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyJ ||
        key == LogicalKeyboardKey.keyZ) {
      setFlag((v) => _keyJump = v);
    } else if (key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.keyX) {
      pressButton(GamepadButton.b, pressed: isDown);
      return true;
    } else if (key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.keyC) {
      pressButton(GamepadButton.x, pressed: isDown);
      return true;
    } else if (key == LogicalKeyboardKey.keyI ||
        key == LogicalKeyboardKey.keyV) {
      pressButton(GamepadButton.y, pressed: isDown);
      return true;
    }

    if (handled) {
      _applyKeyboardAxes();
      return true;
    }
    return false;
  }

  void _applyKeyboardAxes() {
    final wantJump = _keyJump || _keyUp;
    if (wantJump) {
      state.pressed.add(GamepadButton.a);
    } else {
      state.pressed.remove(GamepadButton.a);
    }

    if (!_virtualStickActive) {
      final x = (_keyRight ? 1.0 : 0.0) + (_keyLeft ? -1.0 : 0.0);
      final y = (_keyDown ? 1.0 : 0.0) + (_keyUp ? -1.0 : 0.0);
      state.leftX = x.clamp(-1.0, 1.0);
      state.leftY = y.clamp(-1.0, 1.0);
    }

    void applyDpad(GamepadButton b, bool v) {
      if (v) {
        state.pressed.add(b);
      } else {
        state.pressed.remove(b);
      }
    }

    applyDpad(GamepadButton.left, _keyLeft);
    applyDpad(GamepadButton.right, _keyRight);
    applyDpad(GamepadButton.up, _keyUp);
    applyDpad(GamepadButton.down, _keyDown);
    _emit();
  }

  // —— Virtual overlay API ——

  void setLeftStick(double x, double y) {
    _virtualStickActive = x.abs() > 0.05 || y.abs() > 0.05;
    state.leftX = x.clamp(-1.0, 1.0);
    state.leftY = y.clamp(-1.0, 1.0);
    if (!_virtualStickActive) {
      _applyKeyboardAxes();
    } else {
      _emit();
    }
  }

  void setRightStick(double x, double y) {
    state.rightX = x.clamp(-1.0, 1.0);
    state.rightY = y.clamp(-1.0, 1.0);
    _emit();
  }

  void pressButton(GamepadButton button, {bool pressed = true}) {
    if (pressed) {
      state.pressed.add(button);
      _hapticLight();
    } else {
      state.pressed.remove(button);
    }
    _emit();
  }

  void setDpad({bool? up, bool? down, bool? left, bool? right}) {
    void apply(GamepadButton b, bool? v) {
      if (v == null) return;
      if (v) {
        state.pressed.add(b);
      } else {
        state.pressed.remove(b);
      }
    }

    apply(GamepadButton.up, up);
    apply(GamepadButton.down, down);
    apply(GamepadButton.left, left);
    apply(GamepadButton.right, right);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }

  void _hapticLight() {
    if (!hapticsEnabled || kIsWeb) return;
    // Fire-and-forget; catch platform channel failures (tests / unsupported).
    // ignore: discarded_futures
    HapticFeedback.lightImpact().catchError((_) => null);
  }

  Future<void> dispose() async {
    await _padSub?.cancel();
    await _controller.close();
  }
}
