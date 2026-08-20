import 'dart:io';

/// Skip native gamepad probing when the OS cannot enumerate HID
/// (e.g. Linux VMs without `/dev/input` — the gamepads plugin aborts).
bool get canUseHidGamepads {
  if (Platform.isLinux) {
    try {
      return Directory('/dev/input').existsSync();
    } catch (_) {
      return false;
    }
  }
  return true;
}
