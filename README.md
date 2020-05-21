# Condenser Rails

Provides Condenser integration for the Rails Asset Pipeline.

## Installation

``` ruby
gem 'condenser-rails'
```

Or alternatively `require 'condenser/railtie'` in your `config/application.rb`
if you have Bundler auto-require disabled.

## Usage

### Rake task

**`rake assets:precompile`**

Deployment task that compiles any assets listed in `config.assets.precompile`
to `public/assets`.

**`rake assets:clean`**

Removes old assets from `public/assets`. Useful when doing rolling deploys that
may still be serving old assets while the new ones are being compiled.

**`rake assets:clobber`**

Nuke `public/assets` and remove `config/manifest.json`.

### Initializer options

**`config.assets.precompile`**

Add additional assets to compile on deploy. Defaults to `application.js`,
`application.css` and any `.jpg`, `.png`, or `.gif` files under `app/assets`.

**`config.assets.path`**

Add additional load paths to this Array. Rails includes `app/assets`,
`lib/assets` and `vendor/assets` for you already. Plugins might want to add
their custom paths to this.

**`config.assets.prefix`**

Defaults to `/assets`. Changes the directory to compile assets to.

**`config.assets.compile`**

Enables the Condenser compile environment. If disabled, `Rails.application.assets`
will be `nil` to prevent inadvertent compilation calls. View helpers will depend
on assets being precompiled to `public/assets` in order to link to them.
Initializers expecting `Rails.application.assets` during boot should be accessing
the environment in a `config.assets.configure` block. See below.

**`config.assets.js_minifier`**

The JS minifier to use to minify javascript sources. Default is `:terser`, valid
options are `:terser`, `:uglify`, and `false` to disable minification.

**`config.assets.css_minifier`**

The CSS minifier to use to minify css sources. Default is `:sass`, valid options
are `:sass`, and `false` to disable minification.

**`config.assets.compressors`**

A list of compressors to compress the output with. Each file will be written along
with a compressed version for each compressor. Default is `[:zlib]` which will
add a `.gz` version of each file. Valid options are `:zlib`, and `:brotli`. To
disable set this to an empty array or `false`.

Optionally you may also set this to your own compressor.


**`config.assets.configure`**

Invokes block with environment when the environment is initialized. Allows direct
access to the environment instance and lets you lazily load libraries only needed
for asset compiling.

``` ruby
config.assets.configure do |env|

  require 'my_processor'
  env.register_preprocessor 'application/javascript', MyProcessor
end
```

## Other

### [SRI](http://www.w3.org/TR/SRI/) support

Condenser adds support for subresource integrity checks.

``` ruby
javascript_include_tag :application, integrity: true
# => "<script src="/assets/application.js" integrity="sha256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>"
```

Note that `condenser-rails` only adds integrity hashes to assets when served in a
secure context (over an HTTPS connection or localhost).

## License

Condenser Rails is released under the [MIT License](MIT-LICENSE).