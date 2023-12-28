require_relative 'helper'

class BasicTests < Minitest::Test
  include ConversionTestHelper

  def test_simple_call
    assert_sexp('x.y')
  end

  def test_simple_integer
    assert_sexp('1')
  end
end
