# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "canvas_slug"
  spec.version       = "0.0.1"
  spec.authors       = ["Raphael Weiner"]
  spec.email         = ["rweiner@pivotallabs.com"]
  spec.summary       = "Canvas Slug generation"

  spec.files         = Dir.glob("{lib,test}/**/*") + %w[Rakefile]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "swearjar", "~> 1.4"
end
