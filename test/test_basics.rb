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

  def test_simple_regex
    assert_sexp('/\d/')
  end

  def test_simple_hash
    assert_sexp('{}')
    assert_sexp('{ x: 1 }')
  end

  def test_simple_defn
    assert_sexp('def x; end')
    assert_sexp('def x(a); end')
    assert_sexp('def x(a); b; end')
  end

  def test_simple_ifs
    assert_sexp('if x; end')
    assert_sexp('if x; y; end')
    assert_sexp('if x; y; z; end')
    assert_sexp('if x; y else z end')
  end

  def test_simple_interpolation
    assert_sexp('"#{1}"')
    assert_sexp('"1#{2}"')
    assert_sexp('"1#{2}3"')
  end

  def test_less_simple_interpolation
    assert_sexp('"1#{2}3#{4}"')
    assert_sexp('"1#{2; 3}4"')
  end
end
