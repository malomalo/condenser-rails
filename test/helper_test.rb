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
    @assets = Condenser.new()
    @npm_path = File.expand_path('../../tmp', __FILE__)
    Dir.mkdir(@npm_path) if !Dir.exist?(@npm_path)
    @assets.npm_path = @npm_path
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
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>),
      @view.javascript_include_tag("application")
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>),
      @view.javascript_include_tag("application.js")
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>),
      @view.javascript_include_tag(:application)
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>\n) +
      %(<script src="/assets/another-12f545d083f2ed2e96a98851d1073362785efefd7e190598878280a02189f75d.js" type="module"></script>),
      @view.javascript_include_tag(:application, 'another')

    assert_equal %(<script src="/application.js" type="module"></script>),
      @view.javascript_include_tag("/application")
    assert_equal %(<script src="/application.js" type="module"></script>),
      @view.javascript_include_tag("/application.js")
    assert_equal %(<script src="/application.js" type="module"></script>\n) +
      %(<script src="/assets/another-12f545d083f2ed2e96a98851d1073362785efefd7e190598878280a02189f75d.js" type="module"></script>),
      @view.javascript_include_tag("/application.js", 'another.js')

    assert_equal %(<script src="http://example.com/script"></script>),
      @view.javascript_include_tag("http://example.com/script")
    assert_equal %(<script src="http://example.com/script.js"></script>),
      @view.javascript_include_tag("http://example.com/script.js")
    assert_equal %(<script src="//example.com/script.js"></script>),
      @view.javascript_include_tag("//example.com/script.js")

    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" defer="defer" type="module"></script>),
      @view.javascript_include_tag("application", defer: "defer")
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" async="async" type="module"></script>),
      @view.javascript_include_tag("application", async: "async")
      
    assert_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js"></script>),
      @view.javascript_include_tag("application", type: false)
  end

  def test_stylesheet_link_tag
    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" />),
      @view.stylesheet_link_tag("application")
    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" />),
      @view.stylesheet_link_tag("application.css")
    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" />),
      @view.stylesheet_link_tag(:application)

    assert_dom_equal %(<link rel="stylesheet" href="/elsewhere.css" />),
      @view.stylesheet_link_tag("/elsewhere.css")
    assert_dom_equal %(<link rel="stylesheet" href="/style1.css" />\n<link rel="stylesheet" href="/assets/another-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css" />),
      @view.stylesheet_link_tag("/style1.css", "another.css")

    assert_dom_equal %(<link href="http://www.example.com/styles/style" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style")
    assert_dom_equal %(<link href="http://www.example.com/styles/style.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style.css")
    assert_dom_equal %(<link href="//www.example.com/styles/style.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("//www.example.com/styles/style.css")

    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" media="print" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "print")
    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" media="&lt;hax&gt;" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "<hax>")
  end

  def test_javascript_include_tag_integrity
    assert_dom_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module" integrity="sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module" integrity="#{@view.resolve_assets_with == :manifest ? "sha256-9kV9pQYSIDeJBtbIKoPRDtvAssQnCWcDhAnKiPWJpEQ=" : "sha256-9kV9pQYSIDeJBtbIKoPRDtvAssQnCWcDhAnKiPWJpEQ=" }"></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js" type="module"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" rel="stylesheet" integrity="sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" rel="stylesheet" integrity="#{@view.resolve_assets_with == :manifest ? "sha256-xLWB4bETv0nyrFcxo5QnmQmlI+ZwXJZ03ZClktZMA5c=" : "sha256-xLWB4bETv0nyrFcxo5QnmQmlI+ZwXJZ03ZClktZMA5c="}" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: false)
    assert_dom_equal %(<link href="/assets/application-f715c17313d01a50097094ab0c68bc91dcce41ac112f1073501a25830e4de35e.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: nil)
  end

  def test_javascript_path
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js", @view.javascript_path("application")
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js", @view.javascript_path("application.js")
    assert_equal "/assets/subdir/application-acc587fa9eac334a96da1f9422bf889f561744f9927079f71bcf2bafe882458b.js", @view.javascript_path("subdir/application")
    assert_equal "/assets/subdir/application-acc587fa9eac334a96da1f9422bf889f561744f9927079f71bcf2bafe882458b.js", @view.javascript_path("subdir/application.js")

    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js#hash", @view.javascript_path("application.js#hash")
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js#hash", @view.javascript_path("application#hash")
    assert_equal "/assets/application-4b88aba88b85b6f1b8fa033d51da274c7f10b84f631387f9dca2618513d297d3.js?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")
  end


  def test_stylesheet_path
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css", @view.stylesheet_path("bank")
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css", @view.stylesheet_path("bank.css")
    assert_equal "/assets/subdir/subdir-7d2062fceef53160080b788570a5894f4244afd0b82b6f13c89ee2556736a194.css", @view.stylesheet_path("subdir/subdir")
    assert_equal "/assets/subdir/subdir-7d2062fceef53160080b788570a5894f4244afd0b82b6f13c89ee2556736a194.css", @view.stylesheet_path("subdir/subdir.css")

    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css#hash", @view.stylesheet_path("bank#hash")
    assert_equal "/assets/bank-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")
  end
end

class NoSSLHelperTest < NoHostHelperTest

  def setup
    super

    @view.request = ActionDispatch::Request.new({ "rack.url_scheme" => "http" })
  end

  def test_javascript_include_tag_integrity
    file 'application.js',  'console.log(1);'

    assert_dom_equal %(<script src="/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module" integrity="sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script src="/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module" integrity="sha256-NcFG924SlHfGQGG8hFEeEJDz1NgFlxPmZj3Us1sfdkI="></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    file 'application.css',  'body { background: green; }'

    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css" integrity="sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css" integrity="sha256-G61yc1O+Rg7tdOhiGNazfF3tPymMcQan61x5dILnq/A=" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link rel="stylesheet" href="/assets/application-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css" />),
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
    
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js", @view.javascript_path("application")
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js", @view.javascript_path("application.js")
    assert_equal "https://assets.example.com/assets/super/application-9d431ee05f3bcadfe5a5c513e7a1db861818c107de7bb3481f0c62bcec548dd9.js", @view.javascript_path("super/application")
    assert_equal "https://assets.example.com/super/application.js", @view.javascript_path("/super/application")

    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js#hash", @view.javascript_path("application.js#hash")
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js#hash", @view.javascript_path("application#hash")
    assert_equal "https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")

    assert_dom_equal %(<script src="https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module"></script>),
      @view.javascript_include_tag("application")
    assert_dom_equal %(<script src="https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module"></script>),
      @view.javascript_include_tag("application.js")
    assert_dom_equal %(<script src="https://assets.example.com/assets/application-418f4bac073cda5e457af8955ee97ced477a6a7183d0cdad0576e2ecbc03e259.js" type="module"></script>),
      @view.javascript_include_tag(:application)
  end

  def test_stylesheet_path
    file 'bank.css',            'body { background: red; }'
    file 'subdir/subdir.css',   'body { background: green; }'
    @view.assets_precompile = %w( bank.css subdir/subdir.css )
    
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css", @view.stylesheet_path("bank")
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css", @view.stylesheet_path("bank.css")
    assert_equal "https://assets.example.com/assets/subdir/subdir-d9a577f4cfb493de5d8d613517329e23c1180469c34c6af0709f7e96e9f08696.css", @view.stylesheet_path("subdir/subdir")
    assert_equal "https://assets.example.com/subdir/subdir.css", @view.stylesheet_path("/subdir/subdir.css")

    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css#hash", @view.stylesheet_path("bank#hash")
    assert_equal "https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")

    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank")
    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank.css")
    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-c41460422b053dc59ebe525ceb11a1a2282dc922941f31b008af2f0c25b25c63.css" rel="stylesheet" />),
      @view.stylesheet_link_tag(:bank)
  end

  def test_asset_url
    file 'foo.js', 'console.log(5);'
    file 'logo.png', 'image'
    
    file 'application.js.erb',  "var url = '<%= javascript_path :foo %>';"
    file 'application.css.erb',  'p { background: url(<%= image_path "logo.png" %>); }'
    
    assert_equal "var url = '//assets.example.com/assets/foo-15eabcb8cd4d86fd393170a0976999ee8b8445352bd0e5cf57a357773e1baf2a.js';", @assets.find("application.js").to_s
    assert_equal "p { background: url(//assets.example.com/assets/logo-6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d.png); }", @assets.find("application.css").to_s
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