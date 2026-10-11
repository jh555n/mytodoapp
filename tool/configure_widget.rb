#!/usr/bin/env ruby
require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
runner = project.targets.find { |target| target.name == 'Runner' }
abort 'Runner target is missing. Run tool/bootstrap.sh first.' unless runner
widget = project.targets.find { |target| target.name == 'QuickAddWidget' }
unless widget
  widget = project.new_target(:app_extension, 'QuickAddWidget', :ios, '17.0')
  group = project.main_group.new_group('QuickAddWidget', 'QuickAddWidget')
  source = group.new_file('QuickAddWidget.swift')
  group.new_file('Info.plist')
  widget.add_file_references([source])
  runner.add_dependency(widget)
  phase = runner.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' } ||
    runner.new_copy_files_build_phase('Embed App Extensions')
  phase.dst_subfolder_spec = '13'
  build_file = phase.add_file_reference(widget.product_reference)
  build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
project.targets.each do |target|
  target.build_configurations.each { |config| config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0' }
end
widget.build_configurations.each do |config|
  runner_config = runner.build_configurations.find { |candidate| candidate.name == config.name }
  config.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'dev.dayweave.dayweave.QuickAddWidget',
    'SWIFT_VERSION' => '5.0', 'INFOPLIST_FILE' => 'QuickAddWidget/Info.plist',
    'CODE_SIGN_STYLE' => 'Automatic', 'SKIP_INSTALL' => 'YES',
    'TARGETED_DEVICE_FAMILY' => '1,2', 'CURRENT_PROJECT_VERSION' => '1',
    'MARKETING_VERSION' => '0.1.0', 'APPLICATION_EXTENSION_API_ONLY' => 'YES',
    'DEVELOPMENT_TEAM' => runner_config&.build_settings&.fetch('DEVELOPMENT_TEAM', '') || ''
  })
end
project.save
puts 'QuickAddWidget target registered. Configure signing team in Xcode before device builds.'
