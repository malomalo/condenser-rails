# frozen_string_literal: true

require 'test_helper'
require 'condenser/rails/helper'
require 'action_view'
require 'action_dispatch'
require 'condenser/rails/context'
require 'condenser/rails/helper'
require 'condenser/rails/utils'

class ActionView::Base
  
  def assets_precompile=(value)
    @assets_precompiled = value
    @assets_precompiled_regexes = value.map { |s| Condenser::Rails::Utils.glob_to_regex(s) }
  end
  
end

class HelperTest < ActionView::TestCase
  
  def setup
    @path = Dir.mktmpdir
    @npm_path = File.expand_path('../../tmp', __FILE__)
    Dir.mkdir(@npm_path) if !Dir.exist?(@npm_path)
    @assets = Condenser.new(npm_path: @npm_path)
    @assets.append_path @path
    @assets.context_class.class_eval do
      include ::Condenser::Rails::Context
    end
    
    @manifest_file = File.join(@path, 'assets.json')
    @manifest = Condenser::Manifest.new(@assets, @manifest_file)

    @view = ActionView::Base.new(ActionView::LookupContext.new([]), {}, nil)
    @view.extend ::Condenser::Rails::Helper
    @view.assets              = @assets
    @view.assets_manifest     = @manifest
    @view.resolve_assets_with = :environment
    @view.assets_prefix       = "/assets"
    @view.assets_precompile   = %w( application.js application.css )
    @view.request             = ActionDispatch::Request.new({
      "rack.url_scheme" => "https"
    })

    @assets.context_class.assets_prefix = @view.assets_prefix
    @assets.context_class.config        = @view.config
  end

  def teardown
    FileUtils.remove_entry(@path, true) if @path
  end

  def expected_path(name)
    path = @assets.find(name).export.path
    assert_match(/\A#{Regexp.escape(name.delete_suffix(File.extname(name)))}-\h{64}#{Regexp.escape(File.extname(name))}\z/, path)
    "/assets/#{path}"
  end

  def expected_integrity(name)
    integrity = @assets.find(name).export.integrity
    assert_match(/\Asha256-[A-Za-z0-9+\/]{43}=\z/, integrity)
    integrity
  end

  # def test_foo_and_bar_different_digests
  #   refute_equal @foo_js_digest, @bar_js_digest
  #   refute_equal @foo_css_digest, @bar_css_digest
  # end
  #
  # def assert_servable_asset_url(url)
  #   path, query = url.split("?", 2)
  #   path = path.sub(@view.assets_prefix, "")
  #
  #   status = @assets.call({
  #     'REQUEST_METHOD' => 'GET',
  #     'PATH_INFO' => path,
  #     'QUERY_STRING' => query
  #   })[0]
  #   assert_equal 200, status, "#{url} responded with #{status}"
  # end
end

class NoHostHelperTest < HelperTest

  def setup
    super

    file 'application.js',        "console.log('application');"
    file 'subdir/application.js', "console.log('subdir/application');"
    file 'another.js',            "console.log('another');"
    file 'application.css',       "body { background: blue; }"
    file 'another.css',           "body { background: red; }"
    file 'bank.css',              "body { background: green; }"
    file 'subdir/subdir.css',     "body { background: yellow; }"
    
    @view.assets_precompile = %w(
      application.js
      another.js
      application.css
      another.css
      subdir/application.js
      bank.css
      subdir/subdir.css
    )
    
    @view.request = ActionDispatch::Request.new({ "rack.url_scheme" => "https" })
  end

  def test_javascript_include_tag
    assert_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application")
    assert_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application.js")
    assert_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag(:application)
    assert_equal %(<script src="#{expected_path('application.js')}" type="module"></script>\n) +
      %(<script src="#{expected_path('another.js')}" type="module"></script>),
      @view.javascript_include_tag(:application, 'another')

    assert_equal %(<script src="/application.js" type="module"></script>),
      @view.javascript_include_tag("/application")
    assert_equal %(<script src="/application.js" type="module"></script>),
      @view.javascript_include_tag("/application.js")
    assert_equal %(<script src="/application.js" type="module"></script>\n) +
      %(<script src="#{expected_path('another.js')}" type="module"></script>),
      @view.javascript_include_tag("/application.js", 'another.js')

    assert_equal %(<script src="http://example.com/script"></script>),
      @view.javascript_include_tag("http://example.com/script")
    assert_equal %(<script src="http://example.com/script.js"></script>),
      @view.javascript_include_tag("http://example.com/script.js")
    assert_equal %(<script src="//example.com/script.js"></script>),
      @view.javascript_include_tag("//example.com/script.js")

    assert_equal %(<script src="#{expected_path('application.js')}" defer="defer" type="module"></script>),
      @view.javascript_include_tag("application", defer: "defer")
    assert_equal %(<script src="#{expected_path('application.js')}" async="async" type="module"></script>),
      @view.javascript_include_tag("application", async: "async")
      
    assert_equal %(<script src="#{expected_path('application.js')}"></script>),
      @view.javascript_include_tag("application", type: false)
  end

  def test_javascript_include_tag_preload_links_header_for_detected_module
    response = ActionDispatch::Response.new
    # The view delegates response to its controller
    @view.instance_variable_set(:@_controller, Struct.new(:response).new(response))

    assert_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application", preload_links_header: true)
    assert_equal "<#{expected_path('application.js')}>; rel=modulepreload; as=script; nopush",
      response.headers["link"]
  end

  def test_stylesheet_link_tag
    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" />),
      @view.stylesheet_link_tag("application")
    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" />),
      @view.stylesheet_link_tag("application.css")
    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" />),
      @view.stylesheet_link_tag(:application)

    assert_dom_equal %(<link rel="stylesheet" href="/elsewhere.css" />),
      @view.stylesheet_link_tag("/elsewhere.css")
    assert_dom_equal %(<link rel="stylesheet" href="/style1.css" />\n<link rel="stylesheet" href="#{expected_path('another.css')}" />),
      @view.stylesheet_link_tag("/style1.css", "another.css")

    assert_dom_equal %(<link href="http://www.example.com/styles/style" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style")
    assert_dom_equal %(<link href="http://www.example.com/styles/style.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style.css")
    assert_dom_equal %(<link href="//www.example.com/styles/style.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("//www.example.com/styles/style.css")

    assert_dom_equal %(<link href="#{expected_path('application.css')}" media="print" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "print")
    assert_dom_equal %(<link href="#{expected_path('application.css')}" media="&lt;hax&gt;" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "<hax>")
  end

  def test_javascript_include_tag_integrity
    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module" integrity="sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module" integrity="#{expected_integrity('application.js')}"></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    assert_dom_equal %(<link href="#{expected_path('application.css')}" rel="stylesheet" integrity="sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link href="#{expected_path('application.css')}" rel="stylesheet" integrity="#{expected_integrity('application.css')}" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link href="#{expected_path('application.css')}" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: false)
    assert_dom_equal %(<link href="#{expected_path('application.css')}" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: nil)
  end

  def test_javascript_path
    assert_equal "#{expected_path('application.js')}", @view.javascript_path("application")
    assert_equal "#{expected_path('application.js')}", @view.javascript_path("application.js")
    assert_equal "#{expected_path('subdir/application.js')}", @view.javascript_path("subdir/application")
    assert_equal "#{expected_path('subdir/application.js')}", @view.javascript_path("subdir/application.js")

    assert_equal "#{expected_path('application.js')}?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "#{expected_path('application.js')}?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "#{expected_path('application.js')}#hash", @view.javascript_path("application.js#hash")
    assert_equal "#{expected_path('application.js')}#hash", @view.javascript_path("application#hash")
    assert_equal "#{expected_path('application.js')}?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")
  end


  def test_stylesheet_path
    assert_equal "#{expected_path('bank.css')}", @view.stylesheet_path("bank")
    assert_equal "#{expected_path('bank.css')}", @view.stylesheet_path("bank.css")
    assert_equal "#{expected_path('subdir/subdir.css')}", @view.stylesheet_path("subdir/subdir")
    assert_equal "#{expected_path('subdir/subdir.css')}", @view.stylesheet_path("subdir/subdir.css")

    assert_equal "#{expected_path('bank.css')}?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "#{expected_path('bank.css')}?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "#{expected_path('bank.css')}#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "#{expected_path('bank.css')}#hash", @view.stylesheet_path("bank#hash")
    assert_equal "#{expected_path('bank.css')}?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")
  end
end

class NoSSLHelperTest < NoHostHelperTest

  def setup
    super

    @view.request = ActionDispatch::Request.new({ "rack.url_scheme" => "http" })
  end

  def test_javascript_include_tag_integrity
    file 'application.js',  'console.log(1);'

    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module" integrity="sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module" integrity="#{expected_integrity('application.js')}"></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    file 'application.css',  'body { background: green; }'

    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" integrity="sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" integrity="#{expected_integrity('application.css')}" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link rel="stylesheet" href="#{expected_path('application.css')}" />),
      @view.stylesheet_link_tag("application", integrity: false)
  end

end

class LocalhostHelperTest < NoHostHelperTest
  def setup
    super

    @view.request = ActionDispatch::Request.new({
      "rack.url_scheme" => "http",
      "REMOTE_ADDR" => "127.0.0.1"
    })
  end

end

class RelativeHostHelperTest < HelperTest
  def setup
    super

    @view.config.asset_host = "assets.example.com"
  end

  def test_javascript_path
    file 'application.js',  'console.log(1);'
    file 'super/application.js',  'console.log(2);'
    @view.assets_precompile = %w( application.js super/application.js )
    
    assert_equal "https://assets.example.com#{expected_path('application.js')}", @view.javascript_path("application")
    assert_equal "https://assets.example.com#{expected_path('application.js')}", @view.javascript_path("application.js")
    assert_equal "https://assets.example.com#{expected_path('super/application.js')}", @view.javascript_path("super/application")
    assert_equal "https://assets.example.com/super/application.js", @view.javascript_path("/super/application")

    assert_equal "https://assets.example.com#{expected_path('application.js')}?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "https://assets.example.com#{expected_path('application.js')}?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "https://assets.example.com#{expected_path('application.js')}#hash", @view.javascript_path("application.js#hash")
    assert_equal "https://assets.example.com#{expected_path('application.js')}#hash", @view.javascript_path("application#hash")
    assert_equal "https://assets.example.com#{expected_path('application.js')}?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")

    assert_dom_equal %(<script src="https://assets.example.com#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application")
    assert_dom_equal %(<script src="https://assets.example.com#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag("application.js")
    assert_dom_equal %(<script src="https://assets.example.com#{expected_path('application.js')}" type="module"></script>),
      @view.javascript_include_tag(:application)
  end

  def test_stylesheet_path
    file 'bank.css',            'body { background: red; }'
    file 'subdir/subdir.css',   'body { background: green; }'
    @view.assets_precompile = %w( bank.css subdir/subdir.css )
    
    assert_equal "https://assets.example.com#{expected_path('bank.css')}", @view.stylesheet_path("bank")
    assert_equal "https://assets.example.com#{expected_path('bank.css')}", @view.stylesheet_path("bank.css")
    assert_equal "https://assets.example.com#{expected_path('subdir/subdir.css')}", @view.stylesheet_path("subdir/subdir")
    assert_equal "https://assets.example.com/subdir/subdir.css", @view.stylesheet_path("/subdir/subdir.css")

    assert_equal "https://assets.example.com#{expected_path('bank.css')}?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "https://assets.example.com#{expected_path('bank.css')}?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "https://assets.example.com#{expected_path('bank.css')}#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "https://assets.example.com#{expected_path('bank.css')}#hash", @view.stylesheet_path("bank#hash")
    assert_equal "https://assets.example.com#{expected_path('bank.css')}?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")

    assert_dom_equal %(<link href="https://assets.example.com#{expected_path('bank.css')}" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank")
    assert_dom_equal %(<link href="https://assets.example.com#{expected_path('bank.css')}" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank.css")
    assert_dom_equal %(<link href="https://assets.example.com#{expected_path('bank.css')}" rel="stylesheet" />),
      @view.stylesheet_link_tag(:bank)
  end

  def test_asset_url
    file 'foo.js', 'console.log(5);'
    file 'logo.png', 'image'
    
    file 'application.js.erb',  "var url = '<%= javascript_path :foo %>';"
    file 'application.css.erb',  'p { background: url(<%= image_path "logo.png" %>); }'
    
    assert_equal "var url = '//assets.example.com#{expected_path('foo.js')}';", @assets.find("application.js").to_s
    assert_equal "p { background: url(//assets.example.com#{expected_path('logo.png')}); }", @assets.find("application.css").to_s
  end

  def test_asset_url_depends_on_the_asset
    file 'bank.scss', '$color: green; body { background: $color; }'
    file 'application.css.erb', 'p { background: url(<%= stylesheet_path "bank" %>); }'

    dependencies = @assets.find("application.css").process_dependencies
    assert_equal [[File.join(@path, 'bank.scss'), ['text/css']]], dependencies.map { |d| [d.source_file, d.content_types] }
  end
end

class ManifestHelperTest < NoHostHelperTest

  def setup
    super

    @manifest.export(*@view.assets_precompiled)

    @view.assets              = nil
    @view.assets_manifest     = Condenser::Manifest.new(@manifest_file)
    @view.resolve_assets_with = :manifest
  end

  def test_assets_environment_unavailable
    refute @view.assets
  end
end

class AssetUrlHelperLinksTarget < HelperTest

  def test_precompile_allows_links
    file 'application.css',       "body { background: blue; }"
    @view.assets_precompile = ["application.css"]

    assert @view.asset_path("application.css")
    assert_raises(Condenser::Rails::AssetNotPrecompiledError) do
      assert @view.asset_path("logo.png")
    end
  end

  # def test_links_image_target
  #   assert_match "logo.png", @assets['url.css'].links.to_a[0]
  # end
  #
  # def test_doesnt_track_public_assets
  #   refute_match "does_not_exist.png", @assets['error/missing.css'].links.to_a[0]
  # end
end

class PrecompiledAssetHelperTest < HelperTest

  def test_javascript_precompile
    assert_raises(Condenser::Rails::AssetNotPrecompiled) do
      @view.javascript_include_tag("not_precompiled")
    end
  end

  def test_stylesheet_precompile
    assert_raises(Condenser::Rails::AssetNotPrecompiled) do
      @view.stylesheet_link_tag("not_precompiled")
    end
  end

end