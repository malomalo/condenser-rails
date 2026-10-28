# frozen_string_literal: true

require 'test_helper'
require 'listen'
require 'condenser/rails/task'

# def silence_stderr
#   orig_stderr = $stderr.clone
#   $stderr.reopen File.new('/dev/null', 'w')
#   yield
# ensure
#   $stderr.reopen orig_stderr
# end

class BootTest < ActiveSupport::TestCase

  include ActiveSupport::Testing::Isolation

  attr_reader :app

  def setup
    require 'rails'
    # Can't seem to get initialize to run w/o this
    require 'action_controller/railtie'
    require 'active_support/dependencies'
    require 'tzinfo'

    ENV['RAILS_ENV'] = 'test'

    @rails_root = Pathname.new(Dir.mktmpdir).realpath
    Dir.chdir @rails_root

    @app = Class.new(Rails::Application)
    @app.config.load_defaults Rails.version.split('.').take(2).join('.').to_f
    @app.config.eager_load  = false
    @app.config.time_zone   = 'UTC'
    @app.config.middleware  ||= Rails::Configuration::MiddlewareStackProxy.new
    @app.config.active_support.deprecation = :notify
    ActionView::Base # load ActionView

    Dir.chdir(@app.root) do
      FileUtils.mkdir_p('config')
      File.open("config/manifest.js", "w") do |f|
        f << ""
      end
    end
  end

  def teardown
    Condenser::NodeWorker.stop_workers if defined?(Condenser)
    # Leave @rails_root before deleting it, or getcwd fails after teardown
    Dir.chdir(Dir.tmpdir)
    FileUtils.remove_entry(@rails_root, true) if @rails_root
  end

  def test_initialize
    @app.initialize!
    assert @app.initialized?
  end
end

class TestRailtie < BootTest

  def setup
    super
    require 'condenser/railtie'
  end

  def test_defaults_to_compile_assets_with_env_and_manifest_available
    assert_equal true, app.config.assets.compile

    app.initialize!

    # Env is available
    refute_nil env = app.assets
    assert_kind_of Condenser, env

    # Manifest is always available
    assert manifest = app.assets_manifest
    assert_equal app.assets, manifest.environment
    assert_equal File.join(@rails_root, "public/assets"), manifest.dir

    # Resolves against manifest then environment by default
    assert_equal :environment, app.config.assets.resolve_with

    # Condenser config
    assert            env.cache
    assert_nil        env.minifier_for("application/javascript")
    assert_nil        env.minifier_for("text/css")
    assert_equal      false, env.exporters['application/javascript'].first.options[:minify]
  end

  def test_disabling_compile_has_manifest_but_no_env
    app.configure do
      config.assets.compile = false
    end

    assert_equal false, app.config.assets.compile

    app.initialize!

    # No env when compile is disabled
    assert_nil app.assets

    # Manifest is always available
    refute_nil manifest = app.assets_manifest
    assert_nil manifest.environment
    assert_equal File.join(@rails_root, "public/assets"), manifest.dir

    # Resolves against manifest only
    assert_equal :manifest, app.config.assets.resolve_with
  end

  def test_copies_paths
    FileUtils.mkdir_p File.join(@rails_root, 'javascripts')
    FileUtils.mkdir_p File.join(@rails_root, 'stylesheets')
    
    app.configure do
      config.assets.path << "javascripts"
      config.assets.path << "stylesheets"
    end
    app.initialize!

    assert env = app.assets
    assert_includes(env.path, "#{@rails_root}/javascripts")
    assert_includes(env.path, "#{@rails_root}/stylesheets")
  end

  def test_minifiers
    Rails.env = 'production'
    app.configure do
      config.assets.js_minifier  = :terser
      config.assets.css_minifier = :sass
    end
    app.initialize!

    assert env = app.assets
    assert_kind_of Condenser::TerserMinifier, env.minifier_for("application/javascript")
    assert_kind_of Condenser::SassMinifier, env.minifier_for("text/css")
    assert_equal false, env.exporters['application/javascript'].first.options[:minify]
  end

  def test_rolldown_minifies_by_default_in_production
    Rails.env = 'production'
    app.initialize!

    assert env = app.assets
    assert_equal true, env.exporters['application/javascript'].first.options[:minify]
    assert_nil env.minifier_for("application/javascript")
    assert_kind_of Condenser::LightningCSSMinifier, env.minifier_for("text/css")
  end

  def test_disabling_the_minifiers
    Rails.env = 'production'
    app.configure do
      config.assets.js_minifier  = nil
      config.assets.css_minifier = nil
    end
    app.initialize!

    assert env = app.assets
    assert_equal false, env.exporters['application/javascript'].first.options[:minify]
    assert_nil env.minifier_for("application/javascript")
    assert_nil env.minifier_for("text/css")
  end

  def test_minifiers_do_not_run_in_development
    Rails.env = 'development'
    app.initialize!

    assert env = app.assets
    assert_equal false, env.exporters['application/javascript'].first.options[:minify]
    assert_nil env.minifier_for("application/javascript")
    assert_nil env.minifier_for("text/css")
  end

  def test_minifiers_do_not_run_in_test
    Rails.env = 'test'
    app.initialize!

    assert env = app.assets
    assert_equal false, env.exporters['application/javascript'].first.options[:minify]
    assert_nil env.minifier_for("application/javascript")
    assert_nil env.minifier_for("text/css")
  end

  def test_does_not_listen_for_changes_in_production
    Rails.env = 'production'
    app.initialize!

    assert_equal false, app.assets.build_cache.listening
  end

  def test_listens_for_changes_in_development
    Rails.env = 'development'
    app.initialize!

    skip 'needs a native Listen adapter' if Listen::Adapter.select == Listen::Adapter::Polling
    assert_equal true, app.assets.build_cache.listening
  end

  def test_precompile_task_does_not_listen_for_changes
    Rails.env = 'development'
    app.initialize!
    task = Condenser::Rails::Task.new(app)

    assert_not_same app.assets, task.environment
    assert_equal false, task.environment.build_cache.listening
  end

  def test_watches_config_by_default
    app.initialize!

    assert env = app.assets
    assert_equal [File.join(@rails_root, 'config')], env.watched_paths.map(&:first)
  end

  def test_skips_missing_watch_directories
    app.configure do
      config.assets.watch << 'missing'
    end
    app.initialize!

    assert env = app.assets
    assert_equal [File.join(@rails_root, 'config')], env.watched_paths.map(&:first)
  end

  def test_adding_watch_directories
    FileUtils.mkdir_p(File.join(@rails_root, 'data'))
    other = Pathname.new(Dir.mktmpdir).realpath.to_s
    app.configure do
      config.assets.watch << 'data' << other
    end
    app.initialize!

    assert env = app.assets
    assert_equal [File.join(@rails_root, 'config'), File.join(@rails_root, 'data'), other], env.watched_paths.map(&:first)
  ensure
    FileUtils.remove_entry(other, true) if other
  end

  def test_replacing_watch_directories
    FileUtils.mkdir_p(File.join(@rails_root, 'data'))
    app.configure do
      config.assets.watch = ['data']
    end
    app.initialize!

    assert env = app.assets
    assert_equal [File.join(@rails_root, 'data')], env.watched_paths.map(&:first)
  end

  def test_custom_compressors
    Rails.env = 'production'
    compressor = Class.new(Condenser::Processor).new
    app.configure do
      config.assets.js_minifier  = compressor
      config.assets.css_minifier = compressor
    end
    app.initialize!

    assert env = app.assets
    assert_equal compressor, env.minifier_for("application/javascript")
    assert_equal compressor, env.minifier_for("text/css")
  end

  def test_default_gzip_config
    app.initialize!

    assert env = app.assets
    assert env.writers_for_mime_type('application/javascript').find { |w| w.is_a?(Condenser::ZlibWriter) }
  end

  def test_gzip_config
    app.configure do
      config.assets.compressors = nil
    end
    app.initialize!

    assert env = app.assets
    refute env.writers_for_mime_type('application/javascript').find { |w| w.is_a?(Condenser::ZlibWriter) }
  end

  def test_configure
    FileUtils.mkdir_p(File.join(@rails_root, "javascripts"))
    FileUtils.mkdir_p(File.join(@rails_root, "stylesheets"))
    
    app.configure do
      config.assets.configure do |app, env|
        env.append_path "javascripts"
      end
      config.assets.configure do |app, env|
        env.append_path "stylesheets"
      end
    end
    app.initialize!

    assert env = app.assets

    assert_includes(env.path, File.join(@rails_root, "javascripts"))
    assert_includes(env.path, File.join(@rails_root, "stylesheets"))
  end

  # def test_environment_is_frozen_if_caching_classes
  #   app.configure do
  #     config.cache_classes = true
  #   end
  #   app.initialize!
  #
  #   assert env = app.assets
  #   assert_kind_of Sprockets::CachedEnvironment, env
  # end
  #
  def test_action_view_helper
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s,  "var Foo = 1; console.log(Foo);"
    
    app.configure do
      config.assets.precompile += ["foo.js"]
    end
    app.initialize!
    
    assert_includes app.assets.path, @rails_root.join('app', 'assets', 'javascript').to_s

    assert_equal "/assets", ActionView::Base.assets_prefix
    assert_kind_of Condenser, ActionView::Base.assets
    assert_equal app.assets, ActionView::Base.assets
    assert_equal app.assets_manifest, ActionView::Base.assets_manifest

    @view = action_view
    assert_match %r{\A/assets/foo-\h{64}\.js\z}, @view.javascript_path("foo")

    env = @view.assets
    assert_kind_of Condenser, env
    assert @view.assets.equal?(env), "view didn't return the same cached instance"
  end

  def test_action_view_helper_when_no_compile
    app.configure do
      config.assets.compile = false
    end

    assert_equal false, app.config.assets.compile

    app.initialize!

    refute ActionView::Base.assets
    assert_equal app.assets_manifest, ActionView::Base.assets_manifest

    @view = action_view
    refute @view.assets
    assert_equal app.assets_manifest, @view.assets_manifest
  end

  def test_condenser_context_helper
    app.initialize!

    assert env = app.assets
    assert_equal "/assets", env.context_class.assets_prefix
    assert_nil env.context_class.config.asset_host
  end

  def test_manifest_path
    app.configure do
      config.assets.manifest = Rails.root.join('config','foo','bar.json')
    end
    app.initialize!

    assert manifest = app.assets_manifest
    assert_match %r{config/foo/bar\.json$}, manifest.filename
    assert_match %r{public/assets$}, manifest.dir
  end

  def test_manifest_path_respects_rails_public_path
    app.configure do
      config.paths['public'] = 'test_public'
    end
    app.initialize!

    assert manifest = app.assets_manifest
    assert_match %r{/config/manifest\.json$}, manifest.filename
    assert_match %r{test_public/assets$}, manifest.dir
  end

  def test_load_tasks
    app.initialize!
    app.load_tasks

    assert Rake.application['assets:environment']
    assert Rake.application['assets:precompile']
    assert Rake.application['assets:clean']
    assert Rake.application['assets:clobber']
  end

  def test_task_precompile
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s,  "var Foo = 1; console.log(Foo);"
    
    app.configure do
      config.assets.precompile = ["foo.js"]
    end
    app.initialize!
    app.load_tasks

    path = "#{app.assets_manifest.dir}/foo-*.js"

    # silence_stderr do
      Rake.application['assets:clobber'].execute
    # end
    assert_empty Dir.glob(path)

    # silence_stderr do
      Rake.application['assets:precompile'].execute
    # end
    assert_equal 1, Dir.glob(path).size
    assert_includes File.read(Dir.glob(path).first), "console.log"

    # silence_stderr do
      Rake.application['assets:clobber'].execute
    # end
    assert_empty Dir.glob(path)
  end

  def test_task_precompile_compile_false
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s,  "var Foo = 1; console.log(Foo);"

    app.configure do
      config.assets.compile = false
      config.assets.precompile = ["foo.js"]
    end
    app.initialize!
    app.load_tasks

    path = "#{app.assets_manifest.dir}/foo-*.js"

    # silence_stderr do
      Rake.application['assets:clobber'].execute
    # end
    assert_empty Dir.glob(path)

    # silence_stderr do
      Rake.application['assets:precompile'].execute
    # end
    assert_equal 1, Dir.glob(path).size
    assert_includes File.read(Dir.glob(path).first), "console.log"

    # silence_stderr do
      Rake.application['assets:clobber'].execute
    # end
    assert_empty Dir.glob(path)
  end

  def test_direct_build_environment_call
    FileUtils.mkdir_p File.join(@rails_root, 'javascripts')
    FileUtils.mkdir_p File.join(@rails_root, 'stylesheets')
    
    app.configure do
      config.assets.path << "javascripts"
      config.assets.path << "stylesheets"
    end
    app.initialize!

    assert env = Condenser::Railtie.build_environment(app)
    assert_kind_of Condenser, env

    assert_includes env.path, @rails_root.join("javascripts").to_s
    assert_includes env.path, @rails_root.join("stylesheets").to_s
  end

  def test_defining_an_empty_pipeline
    FileUtils.mkdir_p(File.join(@rails_root, "javascripts"))
    FileUtils.mkdir_p(File.join(@rails_root, "stylesheets"))
    
    app.configure do
      config.assets.pipeline do |condenser|
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal({"application/erb"=>Condenser::Erubi, "application/ejs"=>Condenser::EjsTemplate}, env.templates.transform_values(&:class))
    assert_equal env.preprocessors, {}
    assert_equal({"text/scss"=>{"text/css"=>Condenser::ScssTransformer}, "application/jst"=>{"application/javascript"=>Condenser::JstTransformer}, "image/svg+xml"=>{"application/javascript"=>Condenser::SVGTransformer}}, env.transformers.transform_values { |t| t.transform_values(&:class) })
    assert_equal env.postprocessors, {}
    assert_equal env.minifiers, {}
    assert_equal env.exporters, {}
  end
  
  def test_defining_a_pipeline
    FileUtils.mkdir_p(File.join(@rails_root, "javascripts"))
    FileUtils.mkdir_p(File.join(@rails_root, "stylesheets"))
    
    app.configure do
      config.assets.pipeline do |condenser|
        condenser.register_preprocessor('application/javascript', Condenser::JSAnalyzer.new)
        condenser.register_postprocessor('text/css', ::Condenser::CSSMediaCombinerProcessor.new)
        condenser.register_minifier('application/javascript', Condenser::TerserMinifier.new(condenser.npm_path))
        condenser.register_writer Condenser::ZlibWriter.new
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal({"application/erb"=>Condenser::Erubi, "application/ejs"=>Condenser::EjsTemplate}, env.templates.transform_values(&:class))
    assert_equal({"application/javascript"=>[Condenser::JSAnalyzer]}, env.preprocessors.transform_values { |p| p.map(&:class) })
    assert_equal({"text/scss"=>{"text/css"=>Condenser::ScssTransformer}, "application/jst"=>{"application/javascript"=>Condenser::JstTransformer}, "image/svg+xml"=>{"application/javascript"=>Condenser::SVGTransformer}}, env.transformers.transform_values { |t| t.transform_values(&:class) })
    assert_equal({"text/css"=>[Condenser::CSSMediaCombinerProcessor]}, env.postprocessors.transform_values { |p| p.map(&:class) })
    assert_equal({"application/javascript"=>Condenser::TerserMinifier}, env.minifiers.transform_values(&:class))
    assert_equal env.exporters, {}
  end

  def test_default_exporter_is_rolldown
    app.initialize!

    assert env = app.assets
    assert_equal ["application/javascript"], env.exporters.keys
    assert_equal [Condenser::RolldownProcessor], env.exporters["application/javascript"].map(&:class)
  end

  def test_rolldown_gets_the_npm_path
    app.initialize!

    assert env = app.assets
    assert_equal @rails_root.to_s, env.npm_path
    assert_equal File.join(@rails_root, 'node_modules', 'rolldown'), env.exporters['application/javascript'].first.rolldown_path
  end

  def test_configured_npm_path_is_kept
    FileUtils.mkdir_p(File.join(@rails_root, 'frontend'))
    app.configure do
      config.assets.npm_path = Rails.root.join('frontend')
    end
    app.initialize!

    assert env = app.assets
    assert_equal File.join(@rails_root, 'frontend'), env.npm_path
  end

  def test_a_custom_pipeline_gets_the_npm_path
    npm_path = nil
    app.configure do
      config.assets.pipeline do |condenser|
        npm_path = condenser.npm_path
      end
    end
    app.initialize!

    assert_equal @rails_root.to_s, npm_path
  end

  def test_configuring_the_rolldown_exporter
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s, "import bar from 'bar'; console.log(bar);"
    file @rails_root.join('app', 'assets', 'javascript', 'baz.js').to_s, "export default 'baz';"

    app.configure do
      config.assets.configure do |app, env|
        env.unregister_exporter('application/javascript', Condenser::RolldownProcessor)
        env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(env.npm_path, aliases: {
          'bar' => app.root.join('app/assets/javascript/baz.js').to_s
        }))
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal 1, env.exporters['application/javascript'].size
    assert_kind_of Condenser::RolldownProcessor, env.exporters['application/javascript'].first
    assert_includes env['foo.js'].source, "baz"
  end

  def test_switching_to_the_deprecated_rollup_exporter
    app.configure do
      config.assets.configure do |app, env|
        env.unregister_exporter('application/javascript')
        env.register_exporter('application/javascript', Condenser::RollupProcessor.new(env.npm_path))
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal({"application/javascript"=>[Condenser::RollupProcessor]}, env.exporters.transform_values { |e| e.map(&:class) })
  end

  def test_rolldown_options_are_unchanged_by_default
    app.initialize!

    assert env = app.assets
    assert_equal false, app.config.assets.sourcemap
    assert_equal false, env.sourcemap
    assert_equal Condenser::RolldownProcessor.new(env.npm_path, minify: false).options,
      env.exporters['application/javascript'].first.options
  end

  def test_sourcemap
    [true, :linked, :headers].each do |sourcemap|
      app.config.assets.sourcemap = sourcemap
      assert env = Condenser::Railtie.build_environment(app, true)
      assert_equal sourcemap, env.sourcemap
    end
  end

  def test_sourcemap_with_a_custom_pipeline
    app.configure do
      config.assets.sourcemap = :headers
      config.assets.pipeline do |condenser|
        condenser.register_exporter 'application/javascript', Condenser::RolldownProcessor.new(condenser.npm_path)
      end
    end
    app.initialize!

    assert_equal :headers, app.assets.sourcemap
  end

  def test_sourcemap_with_rolldown_minifying_in_production
    Rails.env = 'production'
    app.configure do
      config.assets.sourcemap = :headers
    end
    app.initialize!

    assert env = app.assets
    assert_equal true, env.exporters['application/javascript'].first.options[:minify]
    assert_equal :headers, env.sourcemap
  end

  def test_invalid_sourcemap
    app.configure do
      config.assets.sourcemap = :hidden
    end

    error = assert_raises(ArgumentError) { app.initialize! }
    assert_equal 'sourcemap must be false, true, :linked or :headers, got :hidden', error.message
  end

  def test_server_serves_the_sourcemap
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s, "var Foo = 1; console.log(Foo);"

    app.configure do
      config.assets.sourcemap = true
    end
    app.initialize!

    path = "/assets/#{app.assets['foo.js'].path}"
    request = Rack::MockRequest.new(app)

    response = request.get(path)
    assert_equal 200, response.status
    assert_equal "#{path}.map", response.headers['sourcemap']

    response = request.get("#{path}.map")
    assert_equal 200, response.status
    assert_includes JSON.parse(response.body)['sourcesContent'].join, "console.log(Foo)"
  end

  def test_server_sends_the_sourcemap_header_for_true_and_headers
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s, "var Foo = 1; console.log(Foo);"
    app.initialize!

    { true => true, linked: false, headers: true }.each do |sourcemap, header|
      app.config.assets.sourcemap = sourcemap
      env = Condenser::Railtie.build_environment(app, true)
      path = "/#{env.find('foo.js').path}"

      response = Rack::MockRequest.new(Condenser::Server.new(env)).get(path)
      assert_equal 200, response.status
      if header
        assert_equal "#{path}.map", response.headers['sourcemap']
      else
        assert_nil response.headers['sourcemap']
      end
      assert_equal sourcemap != :headers, response.body.include?('sourceMappingURL')
    end
  end

  def test_task_precompile_with_a_sourcemap
    file @rails_root.join('app', 'assets', 'javascript', 'foo.js').to_s, "var Foo = 1; console.log(Foo);"

    app.configure do
      config.assets.sourcemap = :linked
      config.assets.precompile = ["foo.js"]
    end
    app.initialize!
    app.load_tasks

    dir = app.assets_manifest.dir
    Rake.application['assets:clobber'].execute
    Rake.application['assets:precompile'].execute

    js = Dir.glob("#{dir}/foo-*.js")
    assert_equal 1, js.size
    assert_equal ["#{js.first}.map"], Dir.glob("#{dir}/foo-*.js.map")
    assert_match %r{\n//# sourceMappingURL=#{Regexp.escape(File.basename(js.first))}\.map\n\z}, File.read(js.first)
    assert_includes JSON.parse(File.read("#{js.first}.map"))['sourcesContent'].join, "console.log(Foo)"

    manifest = JSON.parse(File.read(app.assets_manifest.filename))
    assert_equal "#{File.basename(js.first)}.map", manifest['foo.js']['sourcemap']

    Rake.application['assets:clean'].execute
    assert File.exist?("#{js.first}.map")

    Rake.application['assets:clobber'].execute
    assert_empty Dir.children(dir)
  end


  # def test_quiet_assets_defaults_to_off
  #   app.initialize!
  #   app.load_tasks
  #
  #   assert_equal false, app.config.assets.quiet
  #   refute app.config.middleware.include?(Sprockets::Rails::QuietAssets)
  # end
  #
  # def test_quiet_assets_inserts_middleware
  #   app.configure do
  #     config.assets.quiet = true
  #   end
  #   app.initialize!
  #   app.load_tasks
  #   middleware = app.config.middleware
  #
  #   assert_equal true, app.config.assets.quiet
  #   assert middleware.include?(Sprockets::Rails::QuietAssets)
  #   assert middleware.each_cons(2).include?([Sprockets::Rails::QuietAssets, Rails::Rack::Logger])
  # end
  
  private
    def action_view
      ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    end
end

class TestTailwind < BootTest

  # Tailwind's packages are installed once, here, instead of in each app
  NPM_PATH = File.expand_path('../tmp/npm', __dir__)

  def setup
    super
    require 'condenser/railtie'
    FileUtils.mkdir_p(NPM_PATH)
    # Without one npm installs into the nearest parent with a package.json
    File.write(File.join(NPM_PATH, 'package.json'), '{}') if !File.exist?(File.join(NPM_PATH, 'package.json'))
    app.config.assets.npm_path = NPM_PATH
    FileUtils.mkdir_p(@rails_root.join('app/views'))
    file @rails_root.join('app/assets/stylesheets/application.css').to_s, '@import "tailwindcss";'
  end

  def tailwind(env)
    env.instance_variable_get(:@preprocessors)['text/css']&.find { |p| p.is_a?(Condenser::TailwindProcessor) }
  end

  def css
    app.assets.find('application.css').source
  end

  def wait_until(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until (result = yield)
      return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
    result
  end

  def test_disabled_by_default
    app.initialize!

    assert_equal false, app.config.assets.tailwind
    assert_nil tailwind(app.assets)
    assert_equal '@import "tailwindcss";', css
  end

  def test_registers_the_processor_with_app_and_the_tailwind_sources
    FileUtils.mkdir_p(@rails_root.join('lib/components'))
    other = Pathname.new(Dir.mktmpdir).realpath.to_s
    app.configure do
      config.assets.tailwind = true
      config.assets.tailwind_sources = ['lib/components', other]
    end
    app.initialize!

    assert processor = tailwind(app.assets)
    assert_equal [@rails_root.join('app').to_s, @rails_root.join('lib/components').to_s, other], processor.options[:sources]
    assert_equal false, processor.options[:minify]
    %w[tailwindcss @tailwindcss/node @tailwindcss/oxide].each do |package|
      assert File.exist?(File.join(NPM_PATH, 'node_modules', package, 'package.json')), "#{package} isn't installed"
    end
  ensure
    FileUtils.remove_entry(other, true) if other
  end

  def test_not_registered_with_a_custom_pipeline
    app.configure do
      config.assets.tailwind = true
      config.assets.pipeline { |env| }
    end
    app.initialize!

    assert_nil tailwind(app.assets)
  end

  def test_compiles_the_classes_in_app
    file @rails_root.join('app/views/home/index.html.erb').to_s, '<div class="flex p-4"></div>'
    file @rails_root.join('lib/card.html').to_s, '<div class="grid"></div>'
    app.configure do
      config.assets.tailwind = true
    end
    app.initialize!

    source = css
    assert_includes source, ".flex {\n    display: flex;\n  }"
    assert_includes source, '.p-4 {'
    assert_not_includes source, '.grid {'
  end

  def test_tailwind_sources_adds_a_lib_directory
    file @rails_root.join('app/views/home/index.html.erb').to_s, '<div class="flex"></div>'
    file @rails_root.join('lib/components/card.html').to_s, '<div class="grid"></div>'
    file @rails_root.join('lib/other.html').to_s, '<div class="hidden"></div>'
    app.configure do
      config.assets.tailwind = true
      config.assets.tailwind_sources = ['lib/components']
    end
    app.initialize!

    source = css
    assert_includes source, '.flex {'
    assert_includes source, '.grid {'
    assert_not_includes source, '.hidden {'
  end

  def test_minified_by_the_css_minifier_in_production
    file @rails_root.join('app/views/home/index.html.erb').to_s, '<div class="flex"></div>'
    Rails.env = 'production'
    app.configure do
      config.assets.tailwind = true
    end
    app.initialize!

    assert_equal false, tailwind(app.assets).options[:minify]
    assert_kind_of Condenser::LightningCSSMinifier, app.assets.minifier_for('text/css')
    assert_includes app.assets.find('application.css').export.source, '.flex{display:flex}'
  end

  def test_a_view_edit_rebuilds_the_css_in_development
    file @rails_root.join('app/views/home/index.html.erb').to_s, '<div class="flex"></div>'
    Rails.env = 'development'
    app.configure do
      config.assets.tailwind = true
    end
    app.initialize!
    skip 'needs a native Listen adapter' if Listen::Adapter.select == Listen::Adapter::Polling

    assert_not_includes css, '.grid {'
    assert_includes app.assets.watched_paths.map(&:first), @rails_root.join('app').to_s
    file @rails_root.join('app/views/home/index.html.erb').to_s, '<div class="flex grid"></div>'
    assert wait_until { css.include?('.grid {') }
  end
end
