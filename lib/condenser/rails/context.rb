# frozen_string_literal: true

require 'action_view/helpers'
require 'condenser'

class Condenser
  module Rails
    
    module Context
      include ActionView::Helpers::AssetUrlHelper
      include ActionView::Helpers::AssetTagHelper

      def self.included(klass)
        klass.class_eval do
          class_attribute :config, :assets_prefix
        end
      end

      def compute_asset_path(path, options = {})
        if asset = environment.find(path)
          @dependencies << asset.source_file
          File.join(assets_prefix || "/", asset.path)
        else
          super
        end
      end
    end
    
  end
end
