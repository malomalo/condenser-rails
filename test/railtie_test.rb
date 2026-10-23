# frozen_string_literal: true

require 'test_helper'

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
    Condenser::RolldownProcessor.stop_workers if defined?(Condenser)
    FileUtils.remove_entry(@rails_root, true) if @rails_root
  end

  def test_initialize
    @app.initialize!
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
    app.configure do
      config.assets.js_minifier  = :uglify
      config.assets.css_minifier = :sass
    end
    app.initialize!

    assert env = app.assets
    assert_equal Condenser::UglifyMinifier, env.minifier_for("application/javascript")
    assert_equal Condenser::SassMinifier, env.minifier_for("text/css")
  end

  def test_custom_compressors
    compressor = Class.new
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
    assert_equal env.templates, {"application/erb"=>Condenser::Erubi, "application/ejs"=>Condenser::EjsTemplate}
    assert_equal env.preprocessors, {}
    assert_equal env.transformers, {"text/scss"=>{"text/css"=>Condenser::ScssTransformer}, "application/jst"=>{"application/javascript"=>Condenser::JstTransformer}, "image/svg+xml"=>{"application/javascript"=>Condenser::SVGTransformer}}
    assert_equal env.postprocessors, {}
    assert_equal env.minifiers, {}
    assert_equal env.exporters, {}
  end
  
  def test_defining_a_pipeline
    FileUtils.mkdir_p(File.join(@rails_root, "javascripts"))
    FileUtils.mkdir_p(File.join(@rails_root, "stylesheets"))
    
    app.configure do
      config.assets.pipeline do |condenser|
        condenser.register_preprocessor('application/javascript', Condenser::JSAnalyzer)
        condenser.register_postprocessor('text/css', ::Condenser::CSSMediaCombinerProcessor)
        condenser.register_minifier('application/javascript', Condenser::TerserMinifier)
        condenser.register_writer Condenser::ZlibWriter.new
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal env.templates, {"application/erb"=>Condenser::Erubi, "application/ejs"=>Condenser::EjsTemplate}
    assert_equal env.preprocessors, {"application/javascript"=>[Condenser::JSAnalyzer]}
    assert_equal env.transformers, {"text/scss"=>{"text/css"=>Condenser::ScssTransformer}, "application/jst"=>{"application/javascript"=>Condenser::JstTransformer}, "image/svg+xml"=>{"application/javascript"=>Condenser::SVGTransformer}}
    assert_equal env.postprocessors, {"text/css"=>[Condenser::CSSMediaCombinerProcessor]}
    assert_equal env.minifiers, {"application/javascript"=>Condenser::TerserMinifier}
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
        env.register_exporter('application/javascript', Condenser::RollupProcessor)
      end
    end
    app.initialize!

    assert env = app.assets
    assert_equal({"application/javascript"=>[Condenser::RollupProcessor]}, env.exporters)
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
