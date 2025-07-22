# frozen_string_literal: true

require 'rake'
require 'rake/condensertask'
require 'condenser'
# require 'action_view'
# require 'action_view/base'

module Condenser::Rails
  class Task < Rake::CondenserTask
    attr_accessor :app

    def initialize(app = nil)
      self.app = app
      super
    end

    def environment
      if app
        # Use initialized app.assets or force build an environment if
        # config.assets.compile is disabled
        app.assets || Condenser::Railtie.build_environment(app)
      else
        super
      end
    end

    def output
      if app
        config = app.config
        File.join(config.paths['public'].first, config.assets.prefix)
      else
        super
      end
    end

    def assets
      if app
        app.config.assets.precompile
      else
        super
      end
    end

    def manifest
      if app
        Condenser::Manifest.new(environment, output, app.config.assets.manifest)
      else
        super
      end
    end

    def define
      namespace :assets do
        %w( environment precompile clean clobber ).each do |task|
          Rake::Task[task].clear if Rake::Task.task_defined?(task)
        end

        # Override this task change the loaded dependencies
        desc "Load asset compile environment"
        task :environment do
          # Load full Rails environment by default
          Rake::Task['environment'].invoke
        end

        desc "Compile all the assets named in config.assets.precompile"
        task precompile: :environment do
          with_logger do
            manifest.compile(assets)
          end
        end

        desc "Remove old compiled assets"
        task clean: :environment do
          with_logger do
            manifest.clean
          end
        end

        desc "Remove compiled assets"
        task clobber: :environment do
          with_logger do
            manifest.clobber
          end
        end
      end
    end
  end
end