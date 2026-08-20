# Run on PC + send to phone (USB)

Game Maker works on **Windows PC** and **Android phone**. With your phone plugged into the PC, use the scripts below.

## One-time phone setup

1. Plug phone into PC with a **data USB cable**
2. On phone: **Settings → About phone → tap Build number 7 times** (Developer options)
3. **Developer options → USB debugging → ON**
4. Unlock phone → tap **Allow USB debugging** when prompted

## Send app from PC → phone (Windows)

In PowerShell from the repo folder:

```powershell
git pull origin cursor/mobile-game-maker-3d76
.\scripts\pc_to_phone.bat -Launch
```

Or:

```powershell
.\scripts\pc_to_phone.ps1 -Launch
```

Rebuild then install:

```powershell
.\scripts\pc_to_phone.ps1 -Rebuild -Launch
```

Needs `adb` (comes with [platform-tools](https://developer.android.com/tools/releases/platform-tools) or Flutter’s Android SDK).

## Run on Windows PC

```powershell
.\scripts\run_on_pc.ps1
```

Release exe:

```powershell
.\scripts\run_on_pc.ps1 -Release
```

## Linux / macOS → phone

```bash
chmod +x scripts/pc_to_phone.sh
./scripts/pc_to_phone.sh --launch
./scripts/pc_to_phone.sh --rebuild --launch
```

## What gets installed

- Package: `com.gamemaker.mobile_game_maker`
- APK: `dist/GameMaker-android-arm64.apk`
- Companion **Kaiju** auto-opens on first launch

If install fails with signature conflict:

```powershell
adb uninstall com.gamemaker.mobile_game_maker
.\scripts\pc_to_phone.ps1 -Launch
```
