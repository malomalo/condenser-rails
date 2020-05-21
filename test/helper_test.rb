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

    @view = ActionView::Base.new(ActionView::Base.build_lookup_context(nil))
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
    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag("application")
    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag("application.js")
    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag(:application)
    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>\n) +
      %(<script src="/assets/another-89a8a53cf08859d7020e9abafd978fb38f7760f1ede5b1169e2afa2d8b864c44.js"></script>),
      @view.javascript_include_tag(:application, 'another')

    assert_equal %(<script src="/application.js"></script>),
      @view.javascript_include_tag("/application")
    assert_equal %(<script src="/application.js"></script>),
      @view.javascript_include_tag("/application.js")
    assert_equal %(<script src="/application.js"></script>\n) +
      %(<script src="/assets/another-89a8a53cf08859d7020e9abafd978fb38f7760f1ede5b1169e2afa2d8b864c44.js"></script>),
      @view.javascript_include_tag("/application.js", 'another.js')

    assert_equal %(<script src="http://example.com/script"></script>),
      @view.javascript_include_tag("http://example.com/script")
    assert_equal %(<script src="http://example.com/script.js"></script>),
      @view.javascript_include_tag("http://example.com/script.js")
    assert_equal %(<script src="//example.com/script.js"></script>),
      @view.javascript_include_tag("//example.com/script.js")

    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js" defer="defer"></script>),
      @view.javascript_include_tag("application", defer: "defer")
    assert_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js" async="async"></script>),
      @view.javascript_include_tag("application", async: "async")
  end

  def test_stylesheet_link_tag
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application")
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application.css")
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag(:application)

    assert_dom_equal %(<link href="/elsewhere.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("/elsewhere.css")
    assert_dom_equal %(<link href="/style1.css" media="screen" rel="stylesheet" />\n<link href="/assets/another-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("/style1.css", "another.css")

    assert_dom_equal %(<link href="http://www.example.com/styles/style" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style")
    assert_dom_equal %(<link href="http://www.example.com/styles/style.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("http://www.example.com/styles/style.css")
    assert_dom_equal %(<link href="//www.example.com/styles/style.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("//www.example.com/styles/style.css")

    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="print" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "print")
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="&lt;hax&gt;" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", media: "<hax>")
  end

  def test_javascript_include_tag_integrity
    assert_dom_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js" integrity="sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script integrity="#{@view.resolve_assets_with == :manifest ? "sha256-gVCgjF7iMSc1EdFY7yxU0sDQ/l5YLLvP2JY0BSeO0p8=" : "sha256-4bNaQesJS/g93xf1etK1S7tgxTpPzdgTojDeU3zsRvw=" }" src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" integrity="sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" integrity="#{@view.resolve_assets_with == :manifest ? "sha256-1iLtRg3hwgI7jE88KFY8Tb1GytKXp/d0/AIdA3EV8ss=" : "sha256-3IQ4OEM8qp3sDbFm08tpoROU5vsJflgLpK6gRReNtYA="}" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: false)
    assert_dom_equal %(<link href="/assets/application-d622ed460de1c2023b8c4f3c28563c4dbd46cad297a7f774fc021d037115f2cb.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: nil)
  end

  def test_javascript_path
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js", @view.javascript_path("application")
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js", @view.javascript_path("application.js")
    assert_equal "/assets/subdir/application-51c26a5493dfeda207392f1ea67a323d30fe8a71fe87ed0bf19e72b9e73ee2d7.js", @view.javascript_path("subdir/application")
    assert_equal "/assets/subdir/application-51c26a5493dfeda207392f1ea67a323d30fe8a71fe87ed0bf19e72b9e73ee2d7.js", @view.javascript_path("subdir/application")

    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js#hash", @view.javascript_path("application.js#hash")
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js#hash", @view.javascript_path("application#hash")
    assert_equal "/assets/application-8150a08c5ee231273511d158ef2c54d2c0d0fe5e582cbbcfd8963405278ed29f.js?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")
  end

  def test_stylesheet_path
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css", @view.stylesheet_path("bank")
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css", @view.stylesheet_path("bank.css")
    assert_equal "/assets/subdir/subdir-fc40211db38a80d1bcf40092cb09a91a164fcbc9f4fc06f554d53f990d738428.css", @view.stylesheet_path("subdir/subdir")
    assert_equal "/assets/subdir/subdir-fc40211db38a80d1bcf40092cb09a91a164fcbc9f4fc06f554d53f990d738428.css", @view.stylesheet_path("subdir/subdir.css")

    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css#hash", @view.stylesheet_path("bank#hash")
    assert_equal "/assets/bank-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")
  end
end

class NoSSLHelperTest < NoHostHelperTest

  def setup
    super

    @view.request = ActionDispatch::Request.new({ "rack.url_scheme" => "http" })
  end

  def test_javascript_include_tag_integrity
    file 'application.js',  'console.log(1);'
        
    assert_dom_equal %(<script src="/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application", integrity: "sha-256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs=")

    assert_dom_equal %(<script src="/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application", integrity: true)
    assert_dom_equal %(<script src="/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application", integrity: false)
    assert_dom_equal %(<script src="/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application", integrity: nil)
  end

  def test_stylesheet_link_tag_integrity
    file 'application.css',  'body { background: green; }'

    assert_dom_equal %(<link href="/assets/application-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: "sha-256-5YzTQPuOJz/EpeXfN/+v1sxsjAj/dw8q26abiHZM3A4=")

    assert_dom_equal %(<link href="/assets/application-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("application", integrity: true)
    assert_dom_equal %(<link href="/assets/application-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css" media="screen" rel="stylesheet" />),
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
    
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js", @view.javascript_path("application")
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js", @view.javascript_path("application.js")
    assert_equal "https://assets.example.com/assets/super/application-acb2b9059f81889077f855e7fb19d1ef39247015bb66ffcaa3d1d314e0ea74aa.js", @view.javascript_path("super/application")
    assert_equal "https://assets.example.com/super/application.js", @view.javascript_path("/super/application")

    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js?foo=1", @view.javascript_path("application.js?foo=1")
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js?foo=1", @view.javascript_path("application?foo=1")
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js#hash", @view.javascript_path("application.js#hash")
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js#hash", @view.javascript_path("application#hash")
    assert_equal "https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js?foo=1#hash", @view.javascript_path("application.js?foo=1#hash")

    assert_dom_equal %(<script src="https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application")
    assert_dom_equal %(<script src="https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag("application.js")
    assert_dom_equal %(<script src="https://assets.example.com/assets/application-9001f422e9c91516f6e130be56dd77aa313c52bb7dd18e4bb085067162c9fa70.js"></script>),
      @view.javascript_include_tag(:application)
  end

  def test_stylesheet_path
    file 'bank.css',            'body { background: red; }'
    file 'subdir/subdir.css',   'body { background: green; }'
    @view.assets_precompile = %w( bank.css subdir/subdir.css )
    
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css", @view.stylesheet_path("bank")
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css", @view.stylesheet_path("bank.css")
    assert_equal "https://assets.example.com/assets/subdir/subdir-a8a337e4361e079254f4008b7ba9c86b1946535146563c69cc759caf299151b0.css", @view.stylesheet_path("subdir/subdir")
    assert_equal "https://assets.example.com/subdir/subdir.css", @view.stylesheet_path("/subdir/subdir.css")

    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css?foo=1", @view.stylesheet_path("bank.css?foo=1")
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css?foo=1", @view.stylesheet_path("bank?foo=1")
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css#hash", @view.stylesheet_path("bank.css#hash")
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css#hash", @view.stylesheet_path("bank#hash")
    assert_equal "https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css?foo=1#hash", @view.stylesheet_path("bank.css?foo=1#hash")

    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank")
    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag("bank.css")
    assert_dom_equal %(<link href="https://assets.example.com/assets/bank-98fde70fc322d1c369e1e381081b7f25e84ea64f780f7b61827523c2307e08e7.css" media="screen" rel="stylesheet" />),
      @view.stylesheet_link_tag(:bank)
  end

  def test_asset_url
    file 'foo.js', 'console.log(5);'
    file 'logo.png', 'image'
    
    file 'application.js.erb',  "var url = '<%= javascript_path :foo %>';"
    file 'application.css.erb',  'p { background: url(<%= image_path "logo.png" %>); }'
    
    assert_equal "var url = '//assets.example.com/assets/foo-736b83762e41debca800b8ecdce09eb536ad471d7942432d422fa025c7a47031.js';", @assets.find("application.js").to_s
    assert_equal "p { background: url(//assets.example.com/assets/logo-6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d.png); }", @assets.find("application.css").to_s
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