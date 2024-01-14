require 'prism'
require_relative 'prism_to_ruby_parser/visitor'

module PrismToRubyParser
  def self.parse(string, path = nil, filepath: '(string)')
    prism_out = Prism.parse(string, filepath: path || filepath)
    PrismToRubyParser::Visitor.new.visit(prism_out.value)
  end
end
