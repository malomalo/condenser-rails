# Condenser Rails

Provides Condenser integration for the Rails Asset Pipeline.

Requires Condenser 2.0, Ruby 3.3 or newer, Rails 8.0 or newer, and Node
wherever assets are compiled. Upgrading from an earlier version? See
[Upgrading to Condenser 2](#upgrading-to-condenser-2).

## Installation

``` ruby
gem 'condenser-rails'
gem 'sass-embedded'                     # Sass and SCSS
gem 'lightningcss', '>= 1.33.0.2'       # the default CSS minifier
```

Or alternatively `require 'condenser/railtie'` in your `config/application.rb`
if you have Bundler auto-require disabled.

Sass and SCSS are compiled with [Sass Embedded](https://github.com/sass-contrib/sass-embedded-host-ruby).
CSS is minified with [Lightning CSS](https://lightningcss.dev); `lightningcss`
isn't needed if `config.assets.css_minifier` is `:sass` or `nil`.

### JavaScript bundling

JavaScript is bundled, and minified, with [Rolldown](https://rolldown.rs) by
default. Rolldown runs in Node, so Node must be installed wherever assets are
compiled. The `rolldown` npm package is installed into the npm path
(`config.assets.npm_path`, `Rails.root` by default) the first time it's needed.

To configure Rolldown, replace the default exporter with a configured
`Condenser::RolldownProcessor` instance. Registering the class, as in earlier
versions, no longer works. Pass `minify:` yourself, since it defaults to
`false`:

``` ruby
config.assets.configure do |app, env|
  env.unregister_exporter('application/javascript', Condenser::RolldownProcessor)
  env.register_exporter('application/javascript', Condenser::RolldownProcessor.new(env.npm_path,
    minify: !Rails.env.local?,
    aliases: { 'jquery' => app.root.join('vendor/assets/javascripts/jquery.js').to_s }
  ))
end
```

Rollup is deprecated, and will be removed in Condenser 3.
To use it instead of Rolldown:

``` ruby
config.assets.configure do |app, env|
  env.unregister_exporter('application/javascript')
  env.register_exporter('application/javascript', Condenser::RollupProcessor)
end
```

### Tailwind CSS

To compile stylesheets with [Tailwind CSS](https://tailwindcss.com) v4, turn it
on:

``` ruby
# config/application.rb
config.assets.tailwind = true
```

``` css
/* app/assets/stylesheets/application.css */
@import "tailwindcss";
```

Stylesheets that `@import "tailwindcss"` or `@reference` another one are
compiled by `Condenser::TailwindProcessor`; others are left as they are. Like
Rolldown, it runs in Node, and `tailwindcss`, `@tailwindcss/node` and
`@tailwindcss/oxide` are installed into the npm path when the asset
environment is built, if they aren't there.

Tailwind scans `app/` for class names: the views, components, helpers and
JavaScript. Add other directories with `config.assets.tailwind_sources`,
relative to `Rails.root` or absolute, such as templates in `lib/` or in a gem
or engine:

``` ruby
config.assets.tailwind_sources = [
  'lib/components',
  File.join(Gem.loaded_specs['some_engine'].full_gem_path, 'app/views')
]
```

Each has to be an existing directory. `app/` and the `tailwind_sources` are
watched in development, so editing a template's classes rebuilds the CSS.
`source(...)`, `source(none)` and `@source` in the stylesheet work as in
Tailwind; `@source` paths outside `app/` and the `tailwind_sources` need to be
added to `config.assets.watch` to rebuild a running server's CSS.

Tailwind doesn't minify its output itself: the CSS minifier
(`config.assets.css_minifier`, Lightning CSS by default) minifies the whole
stylesheet outside development and test.

The processor is only added to the default pipeline. With a custom
`config.assets.pipeline`, register it yourself:

``` ruby
config.assets.pipeline do |env|
  # ...
  env.register_preprocessor 'text/css', Condenser::TailwindProcessor.new(env.npm_path,
    sources: [Rails.root.join('app'), Rails.root.join('lib/components')]
  )
end
```

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

**`config.assets.npm_path`**

The directory npm packages, such as `rolldown`, are installed into and loaded
from. Defaults to `Rails.root`.

**`config.assets.watch`**

Directories, relative to `Rails.root` or absolute, that a running server
watches for changes to files assets depend on, without adding them to the load
path. Defaults to `['config']`; missing directories are skipped. A
`depends_on` path starting with `!` is a file relative to `Rails.root`, and
only rebuilds a running server's assets when it's under a load path or a
watched directory:

``` js
// depends_on !config/foo.yml
const foo = <%= YAML.load_file(Rails.root.join('config/foo.yml')).to_json %>;
```

``` ruby
config.assets.watch << 'data'
```

**`config.assets.tailwind`**

Compiles stylesheets that `@import "tailwindcss"` with Tailwind. Defaults to
`false`. See [Tailwind CSS](#tailwind-css).

**`config.assets.tailwind_sources`**

More directories for Tailwind to scan for class names, besides `app/`,
relative to `Rails.root` or absolute. Defaults to `[]`.

**`config.assets.js_minifier`**

The JS minifier to use to minify javascript sources. Valid options are
`:rolldown` (the default, Rolldown minifies its own output), `:terser`, your own
minifier, and `false` or `nil` to disable minification. `:terser` runs in Node,
is npm-installed into the npm path when first used, and turns Rolldown's
minifier off.

**`config.assets.css_minifier`**

The CSS minifier to use to minify css sources. Valid options are
`:lightning_css` (the default, which needs the `lightningcss` gem), `:sass`
(which needs the `sass-embedded` gem), your own minifier, and `false` or `nil`
to disable minification.

Assets are only minified outside the `development` and `test` environments.

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
config.assets.configure do |app, env|
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

The hash is added whenever `integrity: true` is passed, over HTTP as well as
HTTPS.

## Upgrading to Condenser 2

- Requires Condenser 2.0, Ruby 3.3 or newer, Rails 8.0 or newer, and Node
  wherever assets are compiled.
- Replace `gem 'sassc'` with `gem 'sass-embedded'`, and add
  `gem 'lightningcss', '>= 1.33.0.2'` unless `config.assets.css_minifier` is
  `:sass` or `nil`.
- JavaScript is bundled and minified by Rolldown by default. `:uglify` is
  removed; `:terser` still works, and turns Rolldown's minifier off.
- CSS is minified by Lightning CSS by default.
- A custom Rolldown exporter must be an instance:
  `Condenser::RolldownProcessor.new(env.npm_path, minify: !Rails.env.local?, …)`.
- A bare `// depends_on` path that matches nothing now raises
  `Condenser::FileNotFound` (globs don't). Files relative to the app root need
  a `!`, e.g. `// depends_on !config/foo.yml`. `config/` is watched by default
  so a running server picks up changes to them.
- A JavaScript import that can't be resolved now fails the build.
- JSON files can be imported from JavaScript, e.g. `import data from 'data.json'`.
- Sass `@use` and `@import` of npm packages pick the package's stylesheet from
  its `exports` (`sass` or `style` condition), `sass` or `style` field.
- A configured `config.assets.npm_path` is now respected instead of being
  reset to `Rails.root`.
- Tailwind CSS v4 is built in: set `config.assets.tailwind = true`, and
  `config.assets.tailwind_sources` for templates outside `app/`, instead of
  building Tailwind's CSS separately.
- Clear `tmp/cache/assets` and `public/assets` after upgrading.

## License

Condenser Rails is released under the [MIT License](LICENSE).