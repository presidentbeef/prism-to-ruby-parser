# frozen_string_literal: true

require 'minitest'
require 'minitest/autorun'
require 'minitest/pride'
require 'ruby_parser'
require_relative '../lib/prism_to_ruby_parser'

module ConversionTestHelper
  def rp_parse(src)
    RubyParser.new.parse(src)
  end

  def prism_parse(src)
    output = Prism.parse(src)

    assert output.errors.empty?, 'Errors parsing with Prism'

    PrismToRubyParserVisitor.new.visit(output.value)
  end

  def assert_sexp(src)
    from_rp = rp_parse(src)
    from_prism = prism_parse(src)

    assert_same_sexp(from_rp, from_prism)
  end

  def assert_same_sexp(from_rp, from_prism)
    assert_equal from_rp, from_prism

    if from_rp.line
      assert_equal from_rp.line, from_prism.line, "Line mismatch on #{from_rp}"
    end

    from_rp.each_with_index do |e, i|
      if e.is_a? Sexp
        assert_same_sexp e, from_prism[i]
      elsif e.nil?
        assert_nil from_prism[i]
      else
        assert_equal e, from_prism[i]
      end
    end
  end

  def assert_parse(src, from_rp)
    from_prism = prism_parse(src)

    assert_same_sexp(from_rp, from_prism)
  end
end
