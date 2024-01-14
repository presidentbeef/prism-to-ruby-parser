require 'prism'
require_relative 'prism_to_ruby_parser/visitor'

module PrismToRubyParser

  # Convert Ruby code from a string to a RubyParser-style Sexp (s-expression).
  #
  # File name can be specified using a positional argument or keyword argument:
  #
  #   PrismToRubyParser.parse(src, 'my_file')
  #
  # or
  #
  #   PrismToRubyParser.parse(src, filepath: 'my_file')
  #
  # This is the primary interface method for this library.
  def self.parse(string, path = nil, filepath: '(string)')
    prism_ast = Prism.parse(string, filepath: path || filepath)

    self.convert(prism_ast)
  end


  # Convert Prism AST to a RubyParser-style Sexp (s-expression).
  #
  #   prism_ast = Prism.parse('my_ruby(code)')
  #   PrismToRubyParser.convert(prism_ast)
  def self.convert(prism_ast)
    PrismToRubyParser::Visitor.new.visit(prism_ast.value)
  end
end
