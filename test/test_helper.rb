# frozen_string_literal: true

# To make testing/debugging easier, test within this source tree versus an
# installed gem
$LOAD_PATH << File.expand_path('../lib', __FILE__)

require 'minitest/autorun'
require 'minitest/reporters'

require 'condenser'
require "active_support"

ActiveSupport::TestCase.test_order = :random
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

class ActiveSupport::TestCase

  def assert_not_file(path)
    refute File.exist?(path)
  end

  def assert_dir(path)
    assert Dir.exist?(path)
  end

  def assert_file(path, source=nil)
    assert File.exist?(path)
    if source.is_a?(Hash)
      assert_equal(source.deep_stringify_keys, JSON.parse(File.read(path)))
    elsif !source.nil?
      assert_equal(source.rstrip, File.read(path).rstrip)
    end
  end

  def file(name, source)
    if name.start_with?('/')
      dir = File.dirname(name)
      path = name
    else
      dir = File.join(@path, File.dirname(name))
      path = File.join(@path, name)
    end
  
    FileUtils.mkdir_p(dir)
    if File.exist?(path)
      stat = Time.now.to_f - File.stat(path).mtime.to_f
      sleep(1 - stat) if stat < 1
    end
    File.write(path, source)
  end

end