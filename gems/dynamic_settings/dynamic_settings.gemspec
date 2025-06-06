# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "dynamic_settings"
  spec.version       = "0.1.0"
  spec.authors       = ["Jacob Burroughs", "Ethan Vizitei"]
  spec.email         = ["jburroughs@instructure.com", "evizitei@instructure.com"]
  spec.summary       = "Instructure gem for loading config and settings from consul"

  spec.files         = Dir.glob("{lib,spec}/**/*") + %w[test.sh]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 5.0"
  spec.add_dependency "config_file"
  spec.add_dependency "diplomat", ">= 2.5.1"
  spec.add_dependency "logger", "~> 1.5"
  spec.add_dependency "railties"
end
