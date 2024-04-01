require 'rails'
require 'rails/railtie'
require 'action_controller/railtie'
require 'active_support/core_ext/module/remove_method'
require 'active_support/core_ext/numeric/bytes'
require 'condenser'
require 'condenser/rails/utils'
require 'condenser/rails/context'
require 'condenser/rails/helper'
require 'condenser/rails/version'

module Rails
  class Application

    # Undefine Rails' assets method before redefining it, to avoid warnings.
    remove_possible_method :assets
    remove_possible_method :assets=
    
    # Returns Condenser::Manifest for app config.
    attr_accessor :assets

    # Returns Condenser::Manifest for app config.
    attr_accessor :assets_manifest

    # Called from asset helpers to alert you if you reference an asset URL that
    # isn't precompiled and hence won't be available in production.
    def asset_precompiled?(logical_path)
      precompiled_assets.find { |glob| glob =~ logical_path }
    end

    # Lazy-load the precompile list so we don't cause asset compilation at app
    # boot time, but ensure we cache the list so we don't recompute it for each
    # request or test case.
    def precompiled_assets
      @precompiled_assets ||= config.assets.precompile.map { |s| Condenser::Rails::Utils.glob_to_regex(s) }
    end
  end

  class Engine < Railtie
    initializer :append_assets_path, group: :all do |app|
      app.config.assets.path.unshift(*paths["vendor/assets"].existent_directories)
      app.config.assets.path.unshift(*paths["lib/assets"].existent_directories)
      app.config.assets.path.unshift(*paths["app/assets"].existent_directories)
      app.config.assets.npm_path = app.root
    end
  end
end

class Condenser::Railtie < ::Rails::Railtie

  class OrderedOptions < ActiveSupport::OrderedOptions
    def configure(&block)
      self._blocks << block
    end

    def pipeline(&block)
      self._pipeline = block
    end
  end
  
  config.assets = OrderedOptions.new
  config.assets._blocks     = []
  config.assets._pipeline   = nil
  config.assets.path        = []
  config.assets.precompile  = %w(application.css application.js **/*.jpg **/*.png **/*.gif)
  config.assets.prefix      = "/assets"
  config.assets.manifest    = 'config/manifest.json'
  
  config.assets.compile     = true
  config.assets.digest      = true
  config.assets.cache_limit = 1_000.megabytes
  config.assets.compressors = [:zlib]

  config.assets.configure do |app, env|
    config.assets.path.each { |path| env.append_path(path) }
    if config.assets.npm_path && File.directory?(config.assets.npm_path)
      env.append_npm_path(config.assets.npm_path)
    end
  end

  config.assets.configure do |app, env|
    env.context_class.send :include, ::Condenser::Rails::Context
    env.context_class.assets_prefix = config.assets.prefix
    env.context_class.config        = config.action_controller
  end

  config.assets.configure do |app, env|
    env.cache = Condenser::Cache::FileStore.new(
      File.join(app.root, 'tmp', 'cache', 'assets', Rails.env),
      size: config.assets.cache_limit,
      logger: env.logger
    )
  end

  rake_tasks do |app|
    require 'condenser/rails/task'
    Condenser::Rails::Task.new(app)
  end
  
  def resolve_minifier(value)
    if value.is_a?(Symbol) || value.is_a?(String)
      "Condenser::#{value.to_s.camelize}Minifier".constantize
    else
      value
    end
  end
  
  def resolve_writer(value)
    if value.is_a?(Symbol) || value.is_a?(String)
      "Condenser::#{value.to_s.camelize}Writer".constantize.new
    else
      value
    end
  end

  def build_environment(app, initialized = nil)
    initialized = app.initialized? if initialized.nil?
    unless initialized
      ::Rails.logger.warn "Application uninitialized: Try calling YourApp::Application.initialize!"
    end

    env = Condenser.new(pipeline: false, logger: ::Rails.logger, base: app.root.to_s)
    config = app.config

    if config.assets._pipeline
      config.assets._pipeline.call(env)
    else
      env.register_transformer  'text/scss', 'text/css', Condenser::ScssTransformer.new
      env.register_preprocessor 'application/javascript', Condenser::JSAnalyzer
      env.register_exporter       'application/javascript', Condenser::RollupProcessor

      if ::Rails.env != 'development'
        env.register_minifier       'application/javascript', resolve_minifier(config.assets.js_minifier) if config.assets.js_minifier
        env.register_minifier       'text/css', resolve_minifier(config.assets.css_minifier) if config.assets.css_minifier
      end

      env.register_writer Condenser::FileWriter.new
      config.assets.compressors&.each do |writer|
        env.register_writer resolve_writer(writer)
      end
    end

    # Run app.assets.configure blocks
    config.assets._blocks.each do |block|
      block.call(app, env)
    end

    env
  end

  def self.build_manifest(app)
    config = app.config
    
    path = File.join(config.paths['public'].first, config.assets.prefix)
    Condenser::Manifest.new(app.assets, path, config.assets.manifest)
  end

  config.after_initialize do |app|
    config = app.config

    if config.assets.compile
      app.assets = self.build_environment(app, true)
      require 'condenser/server'
      app.routes.prepend do
        mount Condenser::Server.new(app.assets, logger: Rails.logger) => config.assets.prefix
      end
    end

    app.assets_manifest = build_manifest(app)

    if config.assets.resolve_with.nil?
      config.assets.resolve_with = if config.assets.compile
        :environment
      else
        :manifest
      end
    end

    # ActionDispatch::Routing::RouteWrapper.class_eval do
    #   class_attribute :assets_prefix
    #
    #   self.assets_prefix = config.assets.prefix
    # end

    ActiveSupport.on_load(:action_view) do
      include ::Condenser::Rails::Helper

      # Copy relevant config to AV context
      self.assets_prefix        = config.assets.prefix
      if config.assets.compile
        self.assets_precompiled          = config.assets.precompile
        self.assets_precompiled_regexes  = app.precompiled_assets
      end

      self.assets               = app.assets
      self.assets_manifest      = app.assets_manifest

      self.resolve_assets_with  = config.assets.resolve_with
    end
  end

end
