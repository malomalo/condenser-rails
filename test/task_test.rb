# frozen_string_literal: true

require 'test_helper'
require 'condenser/rails/task'

class TaskTest < ActiveSupport::TestCase

  def setup
    @path = Dir.mktmpdir
    @manifest_file = File.join(@path, 'assets.json')
    @npm_path = File.expand_path('../../tmp', __FILE__)
    Dir.mkdir(@npm_path) if !Dir.exist?(@npm_path)
    @assets = Condenser.new(@path, npm_path: @npm_path)
    @manifest = Condenser::Manifest.new(@assets, @manifest_file)
    
    @rake = Rake::Application.new
    Rake.application = @rake

    file 'foo.js',  "var Foo;"

    @task = Condenser::Rails::Task.new do |t|
      t.environment = @assets
      t.manifest    = @manifest
      t.assets      = ['foo.js']
      # t.log_level   = :fatal
    end

    # Stub Rails environment task
    @environment_ran = false
    @rake.define_task Rake::Task, :environment do
      @environment_ran = true
    end
  end

  def teardown
    Rake.application = nil
  end

  def test_precompile
    assert !@environment_ran

    digest_path = @assets['foo.js'].path
    assert_not_file "#{@path}/#{digest_path}"
    assert_not_file @manifest_file
    
    @rake['assets:precompile'].invoke

    assert @environment_ran
    assert_file "#{@path}/#{digest_path}"
    export = @assets['foo.js']
    assert_match(/\A\h{64}\z/, export.etag)
    assert_equal "foo-#{export.etag}.js", export.path
    assert_equal export.size, File.size("#{@path}/#{export.path}")
    assert_equal Digest::SHA256.file("#{@path}/#{export.path}").hexdigest, export.hexdigest
    assert_equal "sha256-#{Digest::SHA256.file("#{@path}/#{export.path}").base64digest}", export.integrity

    assert_file @manifest_file, {
      "foo.js" => {
        path:       export.path,
        etag:       export.etag,
        type:       "module",
        digest:     export.hexdigest,
        size:       export.size,
        integrity:  export.integrity
      }
    }
  end

  def test_clobber
    assert !@environment_ran
    digest_path = @assets['foo.js'].path

    @rake['assets:precompile'].invoke
    assert_file "#{@path}/#{digest_path}"

    assert @environment_ran

    @rake['assets:clobber'].invoke
    assert_dir @path
    assert_not_file "#{@path}/#{digest_path}"
  end

  def test_clean
    oldfile = File.join(@path, 'oldfile.js')
    newfile = File.join(@path, 'newfile.js')
    
    File.write(oldfile, 'old')
    File.write(newfile, 'new')
    FileUtils.touch oldfile, mtime: (Time.now - 5.weeks)
    FileUtils.touch newfile, mtime: (Time.now - 2.weeks)
    
    assert !@environment_ran
    digest_path = @assets['foo.js'].path

    @rake['assets:precompile'].invoke
    assert_file "#{@path}/#{digest_path}"

    assert @environment_ran

    @rake['assets:clean'].invoke
    assert_file "#{@path}/#{digest_path}"
    assert_not_file oldfile
    assert_file newfile
  end

end
