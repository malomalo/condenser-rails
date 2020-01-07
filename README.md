
# Condenser Rails

Provides Condenser integration for the Rails Asset Pipeline.

## Installation

``` ruby
gem 'condenser-rails'
```

Or alternatively `require 'condenser/railtie'` in your `config/application.rb` if you have Bundler auto-require disabled.

## Usage


### Rake task

**`rake assets:precompile`**

Deployment task that compiles any assets listed in `config.assets.precompile` to `public/assets`.

**`rake assets:clean`**

Only removes old assets (keeps the most recent 3 copies) from `public/assets`. Useful when doing rolling deploys that may still be serving old assets while the new ones are being compiled.

**`rake assets:clobber`**

Nuke `public/assets` and remove `config/manifest.json`.

#### Customize

If the basic tasks don't do all that you need, it's straight forward to redefine them and replace them with something more specific to your app.

You can also redefine the task with the built in task generator.

``` ruby
require 'condenser/rails/task'
Condenser::Rails::Task.new(Rails.application) do |t|
  t.environment = lambda { Rails.application.assets }
  t.assets = %w( application.js application.css )
  t.keep = 5
end
```

Each asset task will invoke `assets:environment` first. By default this loads the Rails environment. You can override this task to add or remove dependencies for your specific compilation environment.

Also see [Condenser::Rails::Task](https://github.com/rails/condenser-rails/blob/master/lib/sprockets/rails/task.rb) and [Rake::CondenserTask](https://github.com/rails/condenser/blob/master/lib/rake/condensertask.rb).

### Initializer options

**`config.assets.precompile`**

Add additional assets to compile on deploy. Defaults to `application.js`, `application.css` and any `.jpg`, `.png`, or `.gif` files under `app/assets`.

**`config.assets.path`**

Add additional load paths to this Array. Rails includes `app/assets`, `lib/assets` and `vendor/assets` for you already. Plugins might want to add their custom paths to this.

**`config.assets.quiet`**

Suppresses logger output for asset requests. Uses the `config.assets.prefix` path to match asset requests. Defaults to `false`.

**`config.assets.prefix`**

Defaults to `/assets`. Changes the directory to compile assets to.

**`config.assets.compile`**

Enables the Condenser compile environment. If disabled, `Rails.application.assets` will be `nil` to prevent inadvertent compilation calls. View helpers will depend on assets being precompiled to `public/assets` in order to link to them. Initializers expecting `Rails.application.assets` during boot should be accessing the environment in a `config.assets.configure` block. See below.

**`config.assets.configure`**

Invokes block with environment when the environment is initialized. Allows direct access to the environment instance and lets you lazily load libraries only needed for asset compiling.

``` ruby
config.assets.configure do |env|
  env.js_compressor  = :uglifier
  env.css_compressor = :sass

  require 'my_processor'
  env.register_preprocessor 'application/javascript', MyProcessor

  env.logger = Rails.logger
end
```

**`config.assets.check_precompiled_asset`**

When enabled, an exception is raised for missing assets. This option is enabled by default.

## Complementary plugins

The following plugins provide some extras for the Sprockets Asset Pipeline.

* [sass-rails](https://github.com/rails/sass-rails)

**NOTE** That these plugins are optional. The core coffee-script, sass, less, uglify, (and many more) features are built into Sprockets itself. Many of these plugins only provide generators and extra helpers. You can probably get by without them.


## Other

### [SRI](http://www.w3.org/TR/SRI/) support

Condenser adds support for subresource integrity checks. The spec is still evolving and the API may change in backwards incompatible ways.

``` ruby
javascript_include_tag :application, integrity: true
# => "<script src="/assets/application.js" integrity="sha256-TvVUHzSfftWg1rcfL6TIJ0XKEGrgLyEq6lEpcmrG9qs="></script>"
```

Note that condenser-rails only adds integrity hashes to assets when served in a secure context (over an HTTPS connection or localhost).

## License

Condenser Rails is released under the [MIT License](MIT-LICENSE).