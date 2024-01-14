Gem::Specification.new do |s|
  s.name = 'prism_to_ruby_parser'
  s.version = '0.0.1'
  s.authors = ['Justin Collins']

  s.summary = 'Prism AST to RubyParser AST converter'
  s.description = 'Provides RubyParser compatibility for Prism Ruby parser.'
  s.homepage = 'https://github.com/presidentbeef/prism-to-ruby-parser'
  s.license = 'MIT'

  s.files = Dir['lib/**/*']

  s.add_dependency 'prism', '~> 0.19'
  s.add_dependency 'sexp_processor', '~> 4.0'
  s.add_dependency 'racc', '~> 1.7'
  s.required_ruby_version = '>= 3.3.0'
end
