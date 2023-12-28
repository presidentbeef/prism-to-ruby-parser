require_relative 'helper'

class BasicTests < Minitest::Test
  include ConversionTestHelper

  def test_simple_call
    assert_sexp('x.y')
  end

  def test_call_with_arg
    assert_sexp('x(1)')
  end

  def test_call_with_args
    assert_sexp('x(1, 2)')
  end

  def test_simple_integer
    assert_sexp('1')
  end

  def test_multiple_statements
    assert_sexp("1\n2")
  end

  def test_simple_string
    assert_sexp("'hello there'")
  end

  def test_simple_symbol
    assert_sexp(':abc1')
  end

  def test_simple_assignment
    assert_sexp('x = 1')
  end
end
