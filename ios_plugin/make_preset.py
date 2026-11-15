#!/usr/bin/env python3
"""Writes (or rewrites) the "iOS" export preset in export_presets.cfg.

* version and build number: the same as the game's (project.godot config/version, the Android preset's version/code)
* the camera question iOS shows the first time: "Emerald Break uses the camera to put the pool table in your room
  (AR)." in every language of assets/i18n/strings.csv
* an Xcode project only (application/export_project_only): ios_plugin/ci.sh builds it, unsigned, for Sideloadly

Run it after a version bump; ios_plugin/ci.sh runs it before every iPhone export too.
Usage: python3 ios_plugin/make_preset.py
"""
import csv
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PRESETS = os.path.join(ROOT, "export_presets.cfg")
CAMERA = "Emerald Break uses the camera to put the pool table in your room (AR)."
EXCLUDE = ("tests/*, tools/*, docs/*, assets/models/previews/*, assets/models/source/*, .sync/*, ios_plugin/*, "
           "android_plugin/*, third_party/*, server/*, build/*")


def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def main():
    project = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    version = re.search(r'^config/version="([^"]+)"', project, re.M).group(1)
    text = open(PRESETS, encoding="utf-8").read()
    code = re.search(r"^version/code=(\d+)", text, re.M).group(1)

    rows = list(csv.reader(open(os.path.join(ROOT, "assets/i18n/strings.csv"), encoding="utf-8", newline="")))
    langs = rows[0][1:]
    row = next(r for r in rows if r[0] == CAMERA)
    localized = ", ".join('"%s": "%s"' % (lang, esc(t)) for lang, t in zip(langs, row[1:]) if lang != "en")

    # the iOS preset goes after the existing ones, with the next free number
    blocks = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
    kept = [b for b in blocks if not re.search(r'(?m)^platform="iOS"$', b)]
    numbers = [int(n) for b in kept for n in re.findall(r"(?m)^\[preset\.(\d+)\]$", b)]
    n = max(numbers) + 1 if numbers else 0

    ios = f"""[preset.{n}]

name="iOS"
platform="iOS"
runnable=false
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter="{EXCLUDE}"
export_path="build/ios/EmeraldBreak.ipa"
patches=PackedStringArray()
encryption_include_filters=""
encryption_exclude_filters=""
seed=0
encrypt_pck=false
encrypt_directory=false
script_export_mode=2

[preset.{n}.options]

custom_template/debug=""
custom_template/release=""
architectures/arm64=true
application/app_store_team_id="UNSIGNED00"
application/export_method_debug=1
application/code_sign_identity_debug=""
application/code_sign_identity_release=""
application/provisioning_profile_uuid_debug=""
application/provisioning_profile_uuid_release=""
application/provisioning_profile_specifier_debug=""
application/provisioning_profile_specifier_release=""
application/export_method_release=1
application/bundle_identifier="com.emeraldvortexgames.emeraldbreak"
application/signature=""
application/short_version="{version}"
application/version="{code}"
application/additional_plist_content=""
application/icon_interpolation=4
application/export_project_only=true
application/delete_old_export_files_unconditionally=true
application/min_ios_version="15.0"
application/targeted_device_family=2
modules/camera=false
entitlements/increased_memory_limit=false
entitlements/game_center=false
entitlements/push_notifications="Disabled"
entitlements/additional=""
capabilities/access_wifi=false
capabilities/performance_gaming_tier=false
capabilities/performance_a12=false
capabilities/additional=PackedStringArray()
shader_baker/enabled=false
user_data/accessible_from_files_app=false
user_data/accessible_from_itunes_sharing=false
privacy/camera_usage_description="{esc(CAMERA)}"
privacy/camera_usage_description_localized={{{localized}}}
privacy/microphone_usage_description=""
privacy/microphone_usage_description_localized={{}}
privacy/photolibrary_usage_description=""
privacy/photolibrary_usage_description_localized={{}}
privacy/tracking_enabled=false
privacy/tracking_domains=PackedStringArray()
"""
    out = "".join(kept).rstrip("\n") + "\n\n" + ios
    open(PRESETS, "w", encoding="utf-8").write(out)
    print("iOS preset [preset.%d]: version %s (build %s), camera text in %d languages" % (n, version, code, len(langs)))


if __name__ == "__main__":
    main()
