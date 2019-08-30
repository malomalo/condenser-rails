require 'test_helper'
require 'condenser/rails/task'

class TaskTest < ActiveSupport::TestCase

  def setup
    @path = Dir.mktmpdir
    @manifest_file = File.join(@path, 'assets.json')
    @assets = Condenser.new(@path)
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
    assert_file @manifest_file, {
      "foo.js" => {
        path:       "foo-e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855.js",
        digest:     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        size:       0,
        integrity:  "sha256-47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
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
