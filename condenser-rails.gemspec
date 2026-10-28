$:.unshift File.expand_path("../lib", __FILE__)
require "condenser/rails/version"

Gem::Specification.new do |s|
  s.name = "condenser-rails"
  s.version = Condenser::Rails::VERSION

  s.author = "Jonathan Bracy"
  s.email  = "jonbracy@gmail.com"
  s.homepage = "https://github.com/malomalo/condenser-rails"
  s.summary  = "Condenser integration for Rails"
  s.license  = "MIT"

  s.files = Dir["README.md", "lib/**/*.rb", "LICENSE"]

  s.required_ruby_version = '>= 3.3.0'

  s.add_dependency "condenser", ">= 2.0.0.rc2", "< 3"
  s.add_dependency "actionpack", ">= 8.0"
  s.add_dependency "activesupport", ">= 8.0"
  s.add_development_dependency "railties", ">= 8.0"
  s.add_development_dependency "rake"
  s.add_development_dependency "byebug"
  s.add_development_dependency "sass-embedded"
  s.add_development_dependency "lightningcss", ">= 1.33.0.2"
  s.add_development_dependency "minitest-reporters"
end
