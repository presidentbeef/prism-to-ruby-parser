# Archived

This functionality is built into Prism now, so no need to use this repo!

# RubyParser Compatibility for Prism

[Prism](https://github.com/ruby/prism) is a new portable Ruby parser included in the Ruby standard library.

This library provides translation from Prism abstract syntax tree output to the S-expressions
output by the [ruby_parser](https://www.zenspider.com/projects/ruby_parser.html) gem.

The goal is to get as close as possible to the `ruby_parser` output, but might not hit 100%.

**This project is a work-in-progress!**

## Install

```
gem build prism_to_ruby_parser.gemspec
gem install prism_to_ruby_parser*.gem
``` 

## Usage

### Basic Interface

```ruby
require 'prism_to_ruby_parser'

ruby_code = 'puts "Hello, Prism!"'

PrismToRubyParser.parse(ruby_code) # => s(:call, nil, :puts, s(:str, "Hello, Prism!"))
```

### Options

Right now, only supplying a file path is supported. Timeouts are not (yet?) implemented.

```ruby
# RubyParser style
PrismToRubyParser.parse(ruby_code, file_name)

# Prism style
PrismToRubyParser.parse(ruby_code, filepath: file_name)
```

### AST Conversion

If you already have a Prism AST from somewhere, convert using:

```ruby
PrismToRubyParser.convert(prism_ast)
```

## Development

Bundle to get dependencies:

```
bundle install
```

To run tests:

```
rake
```

Tests are very much failing right now!

## Known Issues

* Numbered block parameters (e.g. `_1`) have different representation
* Alternative arrays in pattern matching (e.g. `case [] in %w[a] ...`) are not handled by Prism
* Parsing errors are not converted to exceptions
* No timeout support

## License

MIT - See LICENSE

Copyright © Justin Collins
