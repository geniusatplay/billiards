#!/bin/bash
# Emerald Break - the iPhone build, step by step (run on a Mac with Xcode; GitHub Actions runs it, see
# .github/workflows/ios.yml). Each step can be run on its own:
#
#   ios_plugin/ci.sh plugin   build the ARKit plugin (godot-cpp 4.5 + src/emerald_ar.mm) into addons/emeraldar/
#   ios_plugin/ci.sh godot    fetch Godot 4.7.2 for macOS and its iOS export template (kept in ~/godot)
#   ios_plugin/ci.sh export   export the game as an Xcode project (build/ios/EmeraldBreak.xcodeproj)
#   ios_plugin/ci.sh ipa      build it, unsigned, into build/ios/EmeraldBreak-<version>.ipa (for Sideloadly)
#   ios_plugin/ci.sh sim      run it on an iPhone simulator with a Dynamic Island: the game's "ios_check" test
#                             (plugin loaded, safe area, AR start-up) -> build/ios/sim/ (pictures + log)
#
# The .ipa is unsigned on purpose: Sideloadly (or AltStore, or Xcode) signs it with your own Apple ID when it
# installs it on the phone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_DIR="${GODOT_DIR:-$HOME/godot}"
GODOT_BIN="$GODOT_DIR/Godot.app/Contents/MacOS/Godot"
MIN_IOS="15.0"
VERSION="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$ROOT/project.godot")"

say() { echo ""; echo "=== $*"; }

step_plugin() {
	cd "$ROOT/ios_plugin"
	if [ ! -f godot-cpp/SConstruct ]; then
		say "fetching godot-cpp (branch 4.5)"
		rm -rf godot-cpp
		git clone --depth 1 --branch 4.5 https://github.com/godotengine/godot-cpp godot-cpp
	fi
	say "building godot-cpp + the EmeraldAR plugin for iOS arm64 (min iOS $MIN_IOS), for phones and for the simulator"
	scons platform=ios arch=arm64 target=template_release ios_min_version="$MIN_IOS" -j"$(sysctl -n hw.ncpu)"
	scons platform=ios arch=arm64 ios_simulator=yes target=template_release ios_min_version="$MIN_IOS" -j"$(sysctl -n hw.ncpu)"
	local lib="bin/libemeraldar.ios.template_release.arm64.a"
	local lib_sim="bin/libemeraldar.ios.template_release.arm64.simulator.a"
	local cpp="godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.a"
	local cpp_sim="godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.simulator.a"
	test -f "$lib" && test -f "$lib_sim" && test -f "$cpp" && test -f "$cpp_sim"
	say "frameworks the plugin asks the app to link (from -fmodules)"
	otool -l "$lib" | grep -A4 LC_LINKER_OPTION | grep string | sort -u || true
	nm -gU "$lib" | grep -q "_emeraldar_init" && echo "entry point emeraldar_init: present"

	local out="$ROOT/addons/emeraldar"
	rm -rf "$out"
	mkdir -p "$out/bin"
	xcodebuild -create-xcframework -library "$lib" -library "$lib_sim" -output "$out/bin/libemeraldar.ios.template_release.xcframework"
	xcodebuild -create-xcframework -library "$cpp" -library "$cpp_sim" -output "$out/bin/libgodot-cpp.ios.template_release.xcframework"
	cp emeraldar.gdextension "$out/"
	ls -la "$out" "$out/bin"
}

step_godot() {
	mkdir -p "$GODOT_DIR"
	local base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
	if [ ! -x "$GODOT_BIN" ]; then
		say "fetching Godot $GODOT_VERSION for macOS"
		curl -fL --retry 3 -o "$GODOT_DIR/godot.zip" "$base/Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
		(cd "$GODOT_DIR" && unzip -q godot.zip && rm godot.zip)
	fi
	if [ ! -f "$GODOT_DIR/ios.zip" ]; then
		say "fetching the Godot $GODOT_VERSION export templates (only ios.zip is kept)"
		curl -fL --retry 3 -o "$GODOT_DIR/templates.tpz" "$base/Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
		(cd "$GODOT_DIR" && unzip -q -j -o templates.tpz "templates/ios.zip" "templates/version.txt" && rm templates.tpz)
	fi
	local tdir="$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable"
	mkdir -p "$tdir"
	cp "$GODOT_DIR/ios.zip" "$GODOT_DIR/version.txt" "$tdir/"
	"$GODOT_BIN" --version
}

step_export() {
	cd "$ROOT"
	test -f addons/emeraldar/emeraldar.gdextension || { echo "run '$0 plugin' first"; exit 1; }
	python3 ios_plugin/make_preset.py
	say "importing the project (the plugin has no macOS library, so Godot prints a harmless error about it here)"
	"$GODOT_BIN" --headless --path . --import 2>&1 | tail -n 40 || true
	grep -q "emeraldar.gdextension" .godot/extension_list.cfg && echo "extension listed for export: yes"
	say "exporting the Xcode project (version $VERSION)"
	rm -rf build/ios
	mkdir -p build/ios
	"$GODOT_BIN" --headless --path . --export-release "iOS" build/ios/EmeraldBreak.ipa 2>&1 | tail -n 60
	test -d build/ios/EmeraldBreak.xcodeproj
	echo "linked static libraries:"
	grep -o 'lib[a-z_-]*\.ios\.[a-z_]*\.xcframework' build/ios/EmeraldBreak.xcodeproj/project.pbxproj | sort -u
}

step_ipa() {
	cd "$ROOT/build/ios"
	say "building the app with Xcode (unsigned)"
	set +e
	xcodebuild -project EmeraldBreak.xcodeproj -scheme EmeraldBreak -configuration Release -sdk iphoneos \
		-destination "generic/platform=iOS" -archivePath EmeraldBreak.xcarchive \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
		archive > xcodebuild.log 2>&1
	local rc=$?
	set -e
	if [ $rc -ne 0 ]; then
		grep -E "error:|Undefined symbols|ld: |\*\* ARCHIVE FAILED" xcodebuild.log | head -n 60
		tail -n 40 xcodebuild.log
		exit $rc
	fi
	tail -n 3 xcodebuild.log
	local app="EmeraldBreak.xcarchive/Products/Applications/EmeraldBreak.app"
	test -d "$app"
	# Chinese: Godot names the folders after the game's locales (zh, zh_TW); add Apple's own names as well
	[ -d "$app/zh.lproj" ] && cp -R "$app/zh.lproj" "$app/zh-Hans.lproj"
	[ -d "$app/zh_TW.lproj" ] && cp -R "$app/zh_TW.lproj" "$app/zh-Hant.lproj"
	say "checks"
	otool -L "$app/EmeraldBreak" | grep -E "ARKit|AVFoundation|CoreVideo" || { echo "ARKit is not linked into the app"; exit 1; }
	plutil -extract NSCameraUsageDescription raw "$app/Info.plist"
	plutil -extract CFBundleShortVersionString raw "$app/Info.plist"
	ls "$app" | grep lproj | tr '\n' ' '; echo
	rm -rf Payload
	mkdir Payload
	cp -R "$app" Payload/
	local ipa="EmeraldBreak-${VERSION}.ipa"
	rm -f "$ipa"
	zip -qry "$ipa" Payload
	ls -la "$ipa"
	shasum -a 256 "$ipa"
}

step_sim() {
	cd "$ROOT/build/ios"
	local bundle="com.emeraldvortexgames.emeraldbreak"
	rm -rf sim
	mkdir -p sim
	say "libraries for the simulator (architectures)"
	local f
	for f in EmeraldBreak.xcframework/*simulator*/*.a libemeraldar*.xcframework/*simulator*/*.a libgodot-cpp*.xcframework/*simulator*/*.a; do
		[ -f "$f" ] && echo "$f: $(lipo -archs "$f" 2>/dev/null || echo '?')"
	done
	say "building for the iOS simulator"
	set +e
	xcodebuild -project EmeraldBreak.xcodeproj -scheme EmeraldBreak -configuration Release -sdk iphonesimulator \
		-destination "generic/platform=iOS Simulator" -derivedDataPath sim_dd ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM="" build > sim/xcodebuild_sim.log 2>&1
	local rc=$?
	set -e
	if [ $rc -ne 0 ]; then
		{ grep -v "ld: warning: ignoring file" sim/xcodebuild_sim.log | grep -E "error|Undefined|referenced from|ld: |BUILD FAILED" | head -n 80; } || true
		{ grep -v "ld: warning: ignoring file" sim/xcodebuild_sim.log | tail -n 40; } || true
		exit $rc
	fi
	local app
	app=$(find sim_dd/Build/Products -maxdepth 2 -name "EmeraldBreak.app" | head -n 1)
	test -d "$app"
	say "an iPhone simulator with a Dynamic Island"
	local udid
	udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devs = [d for rt, ds in json.load(sys.stdin)["devices"].items() if "iOS" in rt for d in ds]
for want in ("iPhone 17 Pro", "iPhone 16 Pro", "Pro", "iPhone"):
    hit = [d for d in devs if want in d["name"]]
    if hit:
        print(hit[-1]["udid"]); break')
	test -n "$udid"
	xcrun simctl list devices | grep "$udid"
	xcrun simctl boot "$udid" || true
	xcrun simctl bootstatus "$udid" -b
	xcrun simctl install "$udid" "$app"
	xcrun simctl spawn "$udid" log stream --level info --style compact --predicate 'process == "EmeraldBreak"' > sim/godot.log 2>&1 &
	local logger=$!
	sleep 2
	say "running the game's ios_check test"
	xcrun simctl launch "$udid" "$bundle" -- --tour=user://tour --only=ios_check
	local i
	for i in $(seq 1 150); do
		grep -q "TOUR done" sim/godot.log && break
		sleep 2
	done
	sleep 2
	xcrun simctl io "$udid" screenshot sim/screen.png || true
	local data
	data=$(xcrun simctl get_app_container "$udid" "$bundle" data)
	find "$data" -name "ios_*.png" -exec cp {} sim/ \;
	kill "$logger" 2>/dev/null || true
	xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
	ls -la sim
	grep -E "\[ios\]|\[ar\]|EmeraldAR|  ok|  FAIL|IOS_CHECK|SCRIPT ERROR|GDExtension" sim/godot.log | cut -c1-300 | head -n 60
	grep -q "IOS_CHECK PASS" sim/godot.log
}

case "${1:-}" in
	plugin) step_plugin ;;
	godot) step_godot ;;
	export) step_export ;;
	ipa) step_ipa ;;
	sim) step_sim ;;
	all) step_plugin; step_godot; step_export; step_ipa ;;
	*) echo "usage: $0 plugin|godot|export|ipa|all"; exit 2 ;;
esac
