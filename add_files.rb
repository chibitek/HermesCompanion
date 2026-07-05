#!/usr/bin/env ruby
require 'xcodeproj'

project_path = File.expand_path('HermesCompanion.xcodeproj', Dir.pwd)
project = Xcodeproj::Project.open(project_path)

# Find the Sources group
sources_group = project.groups.find { |g| g.path == 'Sources' } || project.main_group.children.find { |g| g.respond_to?(:path) && g.path == 'Sources' }
abort 'Sources group not found' unless sources_group

# Find the main target
target = project.targets.find { |t| t.name == 'HermesCompanion' }
abort 'Target HermesCompanion not found' unless target

# New files to add
new_files = [
  'ScanlineEffect.swift',
  'GlitchText.swift',
  'AudioVisualizer.swift',
  'VoiceConversationPage.swift',
]

new_files.each do |filename|
  # Check if already referenced
  existing = project.files.find { |f| f.path == filename || f.path == "Sources/#{filename}" }
  if existing
    puts "#{filename} already in project, skipping"
    next
  end

  file_ref = sources_group.new_reference(filename)
  file_ref.last_known_file_type = 'sourcecode.swift'
  file_ref.source_tree = '<group>'

  target.add_file_references([file_ref])
  puts "Added #{filename}"
end

project.save
puts 'Project saved successfully'
