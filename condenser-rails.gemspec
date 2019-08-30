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

  s.required_ruby_version = '>= 2.5.0'

  s.add_dependency "condenser", ">= 0.0.6"
  s.add_dependency "actionpack", ">= 6.0"
  s.add_dependency "activesupport", ">= 6.0"
  s.add_development_dependency "railties", ">= 6.0"
  s.add_development_dependency "rake"
  s.add_development_dependency "byebug"
  s.add_development_dependency "sass"
  s.add_development_dependency "uglifier"
  s.add_development_dependency "minitest-reporters"
end
