# Adds Firebase to the Xcode project Godot exports (27 Nov 2026; run by ios_plugin/ci.sh before `pod install`):
#   GoogleService-Info.plist into the app's resources, "$(inherited)" in the app's linker / search-path settings (so
#   CocoaPods' settings, -ObjC and the Firebase libraries, reach the app), and Crashlytics' dSYM upload after the build.
#   ruby ios_plugin/firebase_xcode.rb build/ios/EmeraldBreak.xcodeproj EmeraldBreak GoogleService-Info.plist
require 'xcodeproj'

proj_path, target_name, plist = ARGV
project = Xcodeproj::Project.open(proj_path)
target = project.targets.find { |t| t.name == target_name } || project.targets.first
abort "no target in #{proj_path}" if target.nil?
unless target.resources_build_phase.files_references.any? { |r| r && r.path == plist }
  ref = project.main_group.new_reference(plist)
  target.resources_build_phase.add_file_reference(ref, true)
end
target.build_configurations.each do |c|
  %w[OTHER_LDFLAGS LIBRARY_SEARCH_PATHS FRAMEWORK_SEARCH_PATHS HEADER_SEARCH_PATHS].each do |k|
    v = c.build_settings[k]
    arr = v.nil? ? [] : (v.is_a?(Array) ? v : v.split(' '))
    c.build_settings[k] = (['$(inherited)'] + arr).uniq
  end
  c.build_settings['DEBUG_INFORMATION_FORMAT'] = 'dwarf-with-dsym'
end
unless target.shell_script_build_phases.any? { |p| p.name == 'Crashlytics dSYM upload' }
  phase = target.new_shell_script_build_phase('Crashlytics dSYM upload')
  # (never fails the build: a missing network or dSYM only means unsymbolicated crash reports)
  phase.shell_script = "\"${PODS_ROOT}/FirebaseCrashlytics/run\" || echo \"Crashlytics dSYM upload skipped\"\n"
  phase.input_paths = ['${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}',
                       '${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${PRODUCT_NAME}',
                       '${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Info.plist',
                       '$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/GoogleService-Info.plist',
                       '$(TARGET_BUILD_DIR)/$(EXECUTABLE_PATH)']
end
project.save
puts "Firebase: #{plist} in #{target.name}'s resources, $(inherited) linker settings, Crashlytics dSYM upload phase"
