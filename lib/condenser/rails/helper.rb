require 'action_view'
require 'condenser'
require 'active_support/core_ext/class/attribute'

module Condenser::Rails
  
  class AssetNotFound < StandardError; end
  class AssetNotPrecompiled < StandardError; end
  class AssetNotPrecompiledError < AssetNotPrecompiled
    def initialize(source)
      super(<<~MSG)
        Asset was not declared to be precompiled in production. Add
        `Rails.application.config.assets.precompile += %w( #{source} )` to
        `config/initializers/assets.rb` and restart your server
      MSG
    end
  end
    
  module Helper
    include ActionView::Helpers::AssetUrlHelper
    include ActionView::Helpers::AssetTagHelper

    VIEW_ACCESSORS = [
      :assets, :assets_manifest, :assets_precompiled,
      :assets_precompiled_regexes, :assets_prefix, :resolve_assets_with
    ]

    def self.included(klass)
      klass.class_attribute(*VIEW_ACCESSORS)
    end

    def self.extended(obj)
      obj.class_eval do
        attr_accessor(*VIEW_ACCESSORS)
      end
    end

    # Writes over the built in ActionView::Helpers::AssetUrlHelper#compute_asset_path
    # to use the asset pipeline.
    def compute_asset_path(path, options = {})
      if asset_path = resolve_asset_path(path)
        File.join(assets_prefix || "/", asset_path)
      else
        raise Condenser::Rails::AssetNotPrecompiledError.new(path)
        # raise AssetNotFound, "The asset #{ path.inspect } is not present in the asset pipeline.\n"
      end
    end

    # Resolve the asset path against the Condenser manifest or environment.
    # Returns nil if it's an asset we don't know about.
    def resolve_asset_path(path) #:nodoc:
      asset_resolver.asset_path(path)
    end

    # Get integrity for asset path.
    #
    # path    - String path
    # options - Hash options
    #
    # Returns String integrity attribute or nil if no asset was found.
    def asset_integrity(path, options = {})
      asset_resolver.integrity(path)
    end

    # TODO: perhaps prepend this function and add integrity if set to true?
    def javascript_include_tag(*sources)
      options = sources.extract_options!.stringify_keys
      path_options = options.extract!("protocol", "extname", "host", "skip_pipeline").symbolize_keys
      preload_links = []
      use_preload_links_header = options["preload_links_header"].nil? ? preload_links_header : options.delete("preload_links_header")
      nopush = options["nopush"].nil? ? true : options.delete("nopush")
      crossorigin = options.delete("crossorigin")
      crossorigin = "anonymous" if crossorigin == true
      integrity = options["integrity"]
      rel = options["type"] == "module" ? "modulepreload" : "preload"

      sources_tags = sources.uniq.map { |source|
        href = path_to_javascript(source, path_options)
        integrity = if options["integrity"] == true
          asset_integrity(source.to_s.delete_suffix('.js')+'.js')
        elsif options["integrity"] != false
          options["integrity"]
        end
        
        if use_preload_links_header && !options["defer"] && href.present? && !href.start_with?("data:")
          preload_link = "<#{href}>; rel=#{rel}; as=script"
          preload_link += "; crossorigin=#{crossorigin}" unless crossorigin.nil?
          preload_link += "; integrity=#{integrity}" unless integrity.nil?
          preload_link += "; nopush" if nopush
          preload_links << preload_link
        end
        tag_options = {
          "src" => href,
          "crossorigin" => crossorigin
        }.merge!(options.except('integrity'))
        if tag_options["nonce"] == true
          tag_options["nonce"] = content_security_policy_nonce
        end
        tag_options['integrity'] = integrity if integrity
        
        content_tag("script", "", tag_options)
      }.join("\n").html_safe

      if use_preload_links_header
        send_preload_links_header(preload_links)
      end

      sources_tags
    end

    # TODO: perhaps prepend this function and add integrity if set to true?
    def stylesheet_link_tag(*sources)
      options = sources.extract_options!.stringify_keys
      path_options = options.extract!("protocol", "extname", "host", "skip_pipeline").symbolize_keys
      use_preload_links_header = options["preload_links_header"].nil? ? preload_links_header : options.delete("preload_links_header")
      preload_links = []
      crossorigin = options.delete("crossorigin")
      crossorigin = "anonymous" if crossorigin == true
      nopush = options["nopush"].nil? ? true : options.delete("nopush")
      
      sources_tags = sources.uniq.map { |source|
        href = path_to_stylesheet(source, path_options)
        integrity = if options["integrity"] == true
          asset_integrity(source.to_s.delete_suffix('.css')+'.css')
        elsif options["integrity"] != false
          options["integrity"]
        end

        if use_preload_links_header && href.present? && !href.start_with?("data:")
          preload_link = "<#{href}>; rel=preload; as=style"
          preload_link += "; crossorigin=#{crossorigin}" unless crossorigin.nil?
          preload_link += "; integrity=#{integrity}" unless integrity.nil?
          preload_link += "; nopush" if nopush
          preload_links << preload_link
        end
        tag_options = {
          "rel" => "stylesheet",
          "crossorigin" => crossorigin,
          "href" => href
        }.merge!(options.except('integrity'))
        if tag_options["nonce"] == true
          tag_options["nonce"] = content_security_policy_nonce
        end
        tag_options['integrity'] = integrity if integrity

        if apply_stylesheet_media_default && tag_options["media"].blank?
          tag_options["media"] = "screen"
        end
        
        tag(:link, tag_options)
      }.join("\n").html_safe

      if use_preload_links_header
        send_preload_links_header(preload_links)
      end

      sources_tags
    end

    protected
      # Only serve integrity metadata for HTTPS requests:
      #   http://www.w3.org/TR/SRI/#non-secure-contexts-remain-non-secure
      def secure_subresource_integrity_context?
        self.request.nil? || self.request && (self.request.local? || self.request.ssl?)
        # respond_to?(:request) && self.request && (self.request.local? || self.request.ssl?)
      end

      # compute_asset_extname is in AV::Helpers::AssetUrlHelper
      def path_with_extname(path, options)
        path = path.to_s
        "#{path}#{compute_asset_extname(path, options)}"
      end

      # Try each asset resolver and return the first non-nil result.
      def asset_resolver
        @asset_resolver ||= HelperAssetResolvers[resolve_assets_with].new(self)
      end
  end

  # Use a separate module since Helper is mixed in and we needn't pollute
  # the class namespace with our internals.
  module HelperAssetResolvers #:nodoc:
    def self.[](name)
      case name
      when :manifest
        Manifest
      when :environment
        Environment
      else
        raise ArgumentError, "Unrecognized asset resolver: #{name.inspect}. Expected :manifest or :environment"
      end
    end

    class Manifest #:nodoc:
      def initialize(view)
        @manifest = view.assets_manifest
        raise ArgumentError, 'config.assets.resolve_with includes :manifest, but app.assets_manifest is nil' unless @manifest
      end

      def asset_path(path)
        @manifest[path]['path']
      end

      def integrity(path)
        @manifest[path]['integrity']
      end

    end

    class Environment #:nodoc:
      def initialize(view)
        raise ArgumentError, 'config.assets.resolve_with includes :environment, but app.assets is nil' unless view.assets
        @env = view.assets
        @precompiled_assets = view.assets_precompiled_regexes
      end

      def asset_path(path)
        if asset = @env.find(path)
          if !precompiled?(asset.filename)
            raise Condenser::Rails::AssetNotPrecompiledError.new(asset.filename)
          end
          asset.export.path
        end
      end

      def integrity(path)
        @env.find(path)&.export&.integrity
      end

      private

        def precompiled?(path)
          @precompiled_assets.find { |glob| glob =~ path }
        end

    end
  end
end
