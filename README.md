# Emerald Break: iPhone build

Emerald Break is an augmented-reality 8-ball pool game by Emerald Vortex Games, made with Godot 4.7.2.
This repository builds it for **iPhone and iPad**, with walk-around AR through **Apple ARKit**. The
Android version is built separately.

## Getting the app on your iPhone

1. Open **Releases → ios-latest** and download `EmeraldBreak.ipa`.
2. On your computer, open **Sideloadly**, connect the iPhone with a cable, drag the `.ipa` in, enter your
   Apple ID, and press **Start**.
3. On the iPhone: **Settings → General → VPN & Device Management**, trust your Apple ID. If iOS asks, also
   turn on **Settings → Privacy & Security → Developer Mode** and restart.
4. Open Emerald Break. The first time you start a match in AR, iOS asks for the camera: tap **Allow**.

With a free Apple ID the app works for 7 days; after that, install it again the same way. Your progress
stays on the phone and on the game's server.

## How it's built

Every push to `main` runs `.github/workflows/ios.yml` on a GitHub Mac:

| Step | What happens |
|------|--------------|
| `ios_plugin/ci.sh plugin` | builds godot-cpp (4.5) and the ARKit plugin (`ios_plugin/src/emerald_ar.mm`) into `addons/emeraldar/` |
| `ios_plugin/ci.sh godot` | fetches Godot 4.7.2 for macOS and its iOS export template (cached between builds) |
| `ios_plugin/ci.sh export` | writes the iOS export preset (`ios_plugin/make_preset.py`) and exports an Xcode project |
| `ios_plugin/ci.sh ipa` | builds it with Xcode, unsigned, checks that ARKit is linked, and packs the `.ipa` |

The `.ipa` is published as the **ios-latest** release, replacing the previous one.

## The ARKit plugin

`ios_plugin/src/emerald_ar.mm` is a GDExtension that registers an `EmeraldAR` singleton with exactly the same
methods and state layout as the game's Android ARCore plugin. The game's AR code
(`src/ar/arcore_bridge.gd`) therefore drives both platforms the same way. It provides:

- 6-DoF world tracking (the phone's position and direction, as the screen shows it)
- the camera picture (NV12, about 1280×720), plus the mapping that fits it to the screen
- horizontal surfaces (floor, desk) and a ray from the screen centre onto them, used to place the table
- an anchor that keeps the placed table fixed in the room
- the camera permission: iOS asks once, and the game waits for the answer; if it's refused, the game
  offers a button to the app's Settings page

On Android and desktop the plugin isn't present, so the same code is a no-op there.
