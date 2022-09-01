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

    # Override javascript tag helper to provide debugging support.
    #
    # Eventually will be deprecated and replaced by source maps.
    def javascript_include_tag(*sources)
      options = sources.extract_options!.stringify_keys
      path_options = options.extract!("protocol", "extname", "host", "skip_pipeline").symbolize_keys
      early_hints_links = []

      sources_tags = sources.uniq.map { |source|
        href = path_to_javascript(source, path_options)
        early_hints_links << "<#{href}>; rel=preload; as=script"
        tag_options = {
          "src" => href
        }.merge!(options)
        
        if tag_options["nonce"] == true
          tag_options["nonce"] = content_security_policy_nonce
        end
        
        if secure_subresource_integrity_context?
          if tag_options["integrity"] == true
            tag_options["integrity"] = asset_integrity(source.to_s.delete_suffix('.js')+'.js')
          elsif tag_options["integrity"] == false
            tag_options.delete('integrity')
          end
        else
          tag_options.delete('integrity')
        end
        
        content_tag("script", "", tag_options)
      }.join("\n").html_safe

      request.send_early_hints("Link" => early_hints_links.join("\n")) if respond_to?(:request) && request

      sources_tags
    end

    # Override stylesheet tag helper to provide debugging support.
    #
    # Eventually will be deprecated and replaced by source maps.
    def stylesheet_link_tag(*sources)
      options = sources.extract_options!.stringify_keys
      path_options = options.extract!("protocol", "host", "skip_pipeline").symbolize_keys
      early_hints_links = []

      sources_tags = sources.uniq.map { |source|
        href = path_to_stylesheet(source, path_options)
        early_hints_links << "<#{href}>; rel=preload; as=style"
        tag_options = {
          "rel" => "stylesheet",
          "media" => "screen",
          "href" => href
        }.merge!(options)
        
        if secure_subresource_integrity_context?
          if tag_options["integrity"] == true
            tag_options["integrity"] = asset_integrity(source.to_s.delete_suffix('.css')+'.css')
          elsif tag_options["integrity"] == false
            tag_options.delete('integrity')
          end
        else
          tag_options.delete('integrity')
        end

        tag(:link, tag_options)
      }.join("\n").html_safe

      request.send_early_hints("Link" => early_hints_links.join("\n")) if respond_to?(:request) && request

      sources_tags
    end
    
    def svg_tag(path, options=nil)
      source = assets.find(path).to_s
      if options
        tag = source.match(/<svg[^>]*>/)[0]
        attributes = {}
        tag.scan(/([a-zA-Z\-]+)\=\"([^\"]+)\"/).each do |match|
          attributes[match[0]] = match[1]
        end
        options.each do |k, v|
          attributes[k.to_s] = v
        end
        source = source.sub(/<svg[^>]*>/, "<svg#{attributes.map{|k, v| " #{k}=\"#{v}\""}.join("")}>")
      end
      source.html_safe
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
        @env.find(path)&.integrity
      end

      private

        def precompiled?(path)
          @precompiled_assets.find { |glob| glob =~ path }
        end

    end
  end
end
