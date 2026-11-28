#!/bin/bash
# Emerald Online 8 Ball Pool AR - the iPhone build, step by step (run on a Mac with Xcode; GitHub Actions runs it, see
# .github/workflows/ios.yml). Each step can be run on its own:
#
#   ios_plugin/ci.sh plugin   build the ARKit plugin (godot-cpp 4.5 + src/emerald_ar.mm) into addons/emeraldar/
#   ios_plugin/ci.sh godot    fetch Godot 4.7.2 for macOS and its iOS export template (kept in ~/godot)
#   ios_plugin/ci.sh export   export the game as an Xcode project (build/ios/EmeraldBreak.xcodeproj), with Firebase
#                             Analytics + Crashlytics added through CocoaPods when firebase/GoogleService-Info.plist is
#                             there (27 Nov 2026): the build then goes through EmeraldBreak.xcworkspace
#   ios_plugin/ci.sh ipa      build it, unsigned, into build/ios/EmeraldBreak-<version>.ipa (for Sideloadly)
#   ios_plugin/ci.sh sim      run it on an iPhone simulator with a Dynamic Island: the game's "ios_check" test
#                             (plugin loaded, safe area, AR start-up) -> build/ios/sim/ (pictures + log)
#   ios_plugin/ci.sh testflight  sign the app built by "ipa" for the App Store and send it to TestFlight (only when
#                             the repo has the secrets ASC_KEY_P8 and IOS_DIST_KEY; otherwise it says so and stops)
#
# The .ipa is unsigned on purpose: Sideloadly (or AltStore, or Xcode) signs it with your own Apple ID when it
# installs it on the phone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_DIR="${GODOT_DIR:-$HOME/godot}"
GODOT_BIN="$GODOT_DIR/Godot.app/Contents/MacOS/Godot"
MIN_IOS="15.0"
FIREBASE_IOS="${FIREBASE_IOS:-~> 11.15}"     # (the iOS SDK of mid-2025, the same generation as Android's BoM 33.16.0)
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
	# simulator: Godot 4.7.2's simulator engine library is x86_64 only, so the simulator app is x86_64 (Rosetta);
	# arm64 is built too, so the slice fits whichever simulator architecture a later Godot ships
	scons platform=ios arch=arm64 ios_simulator=yes target=template_release ios_min_version="$MIN_IOS" -j"$(sysctl -n hw.ncpu)"
	scons platform=ios arch=x86_64 ios_simulator=yes target=template_release ios_min_version="$MIN_IOS" -j"$(sysctl -n hw.ncpu)"
	local lib="bin/libemeraldar.ios.template_release.arm64.a"
	local cpp="godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.a"
	mkdir -p bin/sim
	local lib_sim="bin/sim/libemeraldar.ios.template_release.simulator.a"
	local cpp_sim="bin/sim/libgodot-cpp.ios.template_release.simulator.a"
	lipo -create bin/libemeraldar.ios.template_release.arm64.simulator.a bin/libemeraldar.ios.template_release.x86_64.simulator.a -output "$lib_sim"
	lipo -create godot-cpp/bin/libgodot-cpp.ios.template_release.arm64.simulator.a godot-cpp/bin/libgodot-cpp.ios.template_release.x86_64.simulator.a -output "$cpp_sim"
	test -f "$lib" && test -f "$lib_sim" && test -f "$cpp" && test -f "$cpp_sim"
	lipo -info "$lib_sim" "$cpp_sim"
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
	step_firebase
}

# Firebase Analytics + Crashlytics (27 Nov 2026): CocoaPods links the SDK into the exported project; the plugin reaches it
# by name (emerald_ar.mm). Without firebase/GoogleService-Info.plist the app is built as before, without Firebase.
step_firebase() {
	cd "$ROOT/build/ios"
	local plist="$ROOT/firebase/GoogleService-Info.plist"
	if [ ! -f "$plist" ]; then
		echo "no firebase/GoogleService-Info.plist: the app is built without Firebase"
		return 0
	fi
	say "adding Firebase Analytics + Crashlytics ($FIREBASE_IOS) with CocoaPods"
	command -v pod >/dev/null || sudo gem install cocoapods
	cp "$plist" GoogleService-Info.plist
	cat > Podfile <<PODS
platform :ios, '$MIN_IOS'
install! 'cocoapods', :warn_for_unused_master_specs_repo => false
target 'EmeraldBreak' do
  pod 'FirebaseAnalytics', '$FIREBASE_IOS'
  pod 'FirebaseCrashlytics', '$FIREBASE_IOS'
end
post_install do |installer|
  installer.pods_project.targets.each do |t|
    t.build_configurations.each do |c|
      c.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '$MIN_IOS'
    end
  end
end
PODS
	ruby "$ROOT/ios_plugin/firebase_xcode.rb" EmeraldBreak.xcodeproj EmeraldBreak GoogleService-Info.plist
	pod install --repo-update 2>&1 | tail -n 25
	test -d EmeraldBreak.xcworkspace
	grep -A3 "FirebaseAnalytics" Podfile.lock | head -n 4
}

# The project or (with Firebase) the workspace CocoaPods made, for xcodebuild.
xc_input() {
	if [ -d EmeraldBreak.xcworkspace ]; then
		echo "-workspace EmeraldBreak.xcworkspace"
	else
		echo "-project EmeraldBreak.xcodeproj"
	fi
}

step_ipa() {
	cd "$ROOT/build/ios"
	say "building the app with Xcode (unsigned)"
	set +e
	xcodebuild $(xc_input) -scheme EmeraldBreak -configuration Release -sdk iphoneos \
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
	if [ -d EmeraldBreak.xcworkspace ]; then
		test -f "$app/GoogleService-Info.plist" || { echo "GoogleService-Info.plist is not in the app"; exit 1; }
		nm "$app/EmeraldBreak" 2>/dev/null | grep -q "_OBJC_CLASS_\$_FIRApp" || { echo "Firebase (FIRApp) is not linked into the app"; exit 1; }
		echo "Firebase: linked, GoogleService-Info.plist bundled, collection off until the player's choice:"
		plutil -extract FIREBASE_ANALYTICS_COLLECTION_ENABLED raw "$app/Info.plist" || true
	fi
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
	# the engine's simulator library is x86_64 only: build an x86_64 simulator app, run through Rosetta
	if ! arch -x86_64 /usr/bin/true 2>/dev/null; then
		say "installing Rosetta on the build Mac (for the x86_64 simulator app)"
		sudo softwareupdate --install-rosetta --agree-to-license || true
	fi
	local sim_arch
	sim_arch=$(lipo -archs EmeraldBreak.xcframework/*simulator*/libgodot.a 2>/dev/null | tr ' ' '\n' | grep -m1 -E "arm64|x86_64" || echo x86_64)
	lipo -archs EmeraldBreak.xcframework/*simulator*/libgodot.a 2>/dev/null | grep -q arm64 && sim_arch=arm64
	say "building for the iOS simulator ($sim_arch)"
	set +e
	xcodebuild $(xc_input) -scheme EmeraldBreak -configuration Release -sdk iphonesimulator \
		-destination "generic/platform=iOS Simulator" -derivedDataPath sim_dd ARCHS="$sim_arch" ONLY_ACTIVE_ARCH=NO \
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
	# the cloud Mac has no GPU: the simulator draws with Apple's software renderer (and the x86_64 app runs
	# through Rosetta), so the first 3D frames take minutes. Wait up to 20 minutes for the test's verdict.
	local i
	for i in $(seq 1 120); do
		grep -q "IOS_CHECK\|TOUR done" sim/godot.log && break
		[ $((i % 6)) -eq 0 ] && echo "  ... $((i * 10)) s, $(wc -l < sim/godot.log) log lines"
		sleep 10
	done
	for i in $(seq 1 18); do
		grep -q "TOUR done" sim/godot.log && break
		sleep 10
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

# TestFlight (26 Nov 2026, Randy: TestFlight for the iPhone testers, signed uploads from this build). The app from
# "ipa" (still unsigned) is signed here with the team's Apple Distribution certificate and the App Store profile
# "Emerald 8 Ball Pool App Store" (Game Center + Sign in with Apple), then uploaded with the App Store Connect API key.
# Secrets (GitHub: Settings > Secrets and variables > Actions): ASC_KEY_P8 = the .p8 file's text, IOS_DIST_KEY = the
# certificate's private key (keys\ios_distribution_key.pem on Randy's PC). The certificate and the profile come from
# Apple through the API (ios_plugin/asc.py). Each upload gets the build number of the GitHub run.
step_testflight() {
	if [ -z "${ASC_KEY_P8:-}" ] || [ -z "${IOS_DIST_KEY:-}" ] || [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ]; then
		say "TestFlight: the signing secrets are not in the repo yet - skipped"
		return 0
	fi
	cd "$ROOT/build/ios"
	local app_src="EmeraldBreak.xcarchive/Products/Applications/EmeraldBreak.app"
	test -d "$app_src"
	local work="${RUNNER_TEMP:-/tmp}/testflight"
	rm -rf "$work"
	mkdir -p "$work"
	chmod 700 "$work"
	local kc="$work/sign.keychain-db"
	local kcpass p12pass
	kcpass="$(openssl rand -hex 16)"
	p12pass="$(openssl rand -hex 16)"
	cleanup_tf() {
		security delete-keychain "$kc" 2>/dev/null || true
		rm -rf "$work" ~/.appstoreconnect/private_keys
	}
	trap cleanup_tf EXIT
	mkdir -p ~/.appstoreconnect/private_keys
	( umask 077; printf '%s\n' "$ASC_KEY_P8" > ~/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8
	  printf '%s\n' "$IOS_DIST_KEY" > "$work/dist.key" )

	say "TestFlight: the certificate and the App Store profile from Apple"
	python3 -m pip install --user --break-system-packages -q pyjwt cryptography 2>/dev/null \
		|| python3 -m pip install --user -q pyjwt cryptography
	python3 "$ROOT/ios_plugin/asc.py" fetch "$work"

	say "TestFlight: a keychain with the certificate"
	/usr/bin/openssl x509 -inform DER -in "$work/dist.cer" -out "$work/dist.pem"
	/usr/bin/openssl pkcs12 -export -inkey "$work/dist.key" -in "$work/dist.pem" -out "$work/dist.p12" -passout "pass:$p12pass"
	security create-keychain -p "$kcpass" "$kc"
	security set-keychain-settings -lut 3600 "$kc"
	security unlock-keychain -p "$kcpass" "$kc"
	security import "$work/dist.p12" -k "$kc" -P "$p12pass" -T /usr/bin/codesign -T /usr/bin/security
	security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kcpass" "$kc" > /dev/null
	security list-keychains -d user -s "$kc" $(security list-keychains -d user | tr -d '"')
	# Apple's intermediate certificate (usually installed with Xcode already)
	curl -fsSL -o "$work/AppleWWDRCAG3.cer" https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer \
		&& security import "$work/AppleWWDRCAG3.cer" -k "$kc" 2>/dev/null || true
	local ident
	ident="$(security find-identity -v -p codesigning "$kc" | awk '/Apple Distribution|iPhone Distribution/ {print $2; exit}')"
	test -n "$ident" || { security find-identity -v -p codesigning "$kc"; echo "no distribution identity"; exit 1; }

	say "TestFlight: signing the app"
	rm -rf "$work/Payload"
	mkdir -p "$work/Payload"
	cp -R "$app_src" "$work/Payload/"
	local app="$work/Payload/EmeraldBreak.app"
	local build="${GITHUB_RUN_NUMBER:-$(date +%s)}"
	plutil -replace CFBundleVersion -string "$build" "$app/Info.plist"
	plutil -replace ITSAppUsesNonExemptEncryption -bool NO "$app/Info.plist"
	cp "$work/app.mobileprovision" "$app/embedded.mobileprovision"
	security cms -D -i "$work/app.mobileprovision" > "$work/profile.plist"
	/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$work/profile.plist" > "$work/ent.plist"
	local team appid
	team="$(/usr/libexec/PlistBuddy -c "Print :com.apple.developer.team-identifier" "$work/ent.plist")"
	appid="$(/usr/libexec/PlistBuddy -c "Print :application-identifier" "$work/ent.plist")"
	# the app's own keychain group instead of the profile's wildcard
	/usr/libexec/PlistBuddy -c "Delete :keychain-access-groups" "$work/ent.plist" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :keychain-access-groups array" -c "Add :keychain-access-groups:0 string $appid" "$work/ent.plist"
	/usr/libexec/PlistBuddy -c "Print :com.apple.developer.game-center" "$work/ent.plist" > /dev/null \
		|| { echo "the profile has no Game Center: regenerate it"; exit 1; }
	echo "team $team, app $appid, build $(plutil -extract CFBundleShortVersionString raw "$app/Info.plist") ($build)"
	find "$app" -name "_CodeSignature" -type d -prune -exec rm -rf {} +
	local f
	if [ -d "$app/Frameworks" ]; then
		for f in "$app"/Frameworks/*; do
			[ -e "$f" ] || continue
			codesign -f -s "$ident" --keychain "$kc" "$f"
		done
	fi
	codesign -f -s "$ident" --keychain "$kc" --entitlements "$work/ent.plist" "$app"
	codesign --verify --deep --strict "$app"
	codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - | grep -E "game-center|applesignin|beta-reports|application-identifier" || true
	local ipa="$work/EmeraldBreak-${VERSION}-${build}.ipa"
	( cd "$work" && zip -qry "$ipa" Payload )
	ls -la "$ipa"

	say "TestFlight: uploading build $build"
	local out
	if out="$(xcrun altool --upload-app -f "$ipa" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1)"; then
		echo "$out" | tail -n 15
	else
		echo "$out" | tail -n 40
		say "TestFlight: trying the newer upload command"
		xcrun altool --upload-package "$ipa" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" \
			--apple-id "${ASC_APP_ID:-6839666893}" --bundle-id com.emeraldvortexgames.emeraldbreak \
			--bundle-version "$build" --bundle-short-version-string "$VERSION" 2>&1 | tail -n 40
		test "${PIPESTATUS[0]}" -eq 0
	fi
	say "TestFlight: sent. Apple processes it for a few minutes, then the \"Testers\" group gets it."
}

case "${1:-}" in
	plugin) step_plugin ;;
	godot) step_godot ;;
	export) step_export ;;
	ipa) step_ipa ;;
	sim) step_sim ;;
	testflight) step_testflight ;;
	all) step_plugin; step_godot; step_export; step_ipa ;;
	*) echo "usage: $0 plugin|godot|export|ipa|sim|testflight|all"; exit 2 ;;
esac
