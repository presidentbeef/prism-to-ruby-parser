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

  def test_call_with_block
    assert_sexp('x do; end')
  end

  def test_call_with_block_simple_args
    assert_sexp('x do |y| end')
  end

  def test_call_with_block_body
    assert_sexp('x do; 1; end')
    assert_sexp('x do; 1; 2; end')
  end

  def test_call_with_kwargs
    assert_sexp('x(**args)')
    assert_sexp('def y(**); x(**); end')
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

  def test_defn_kwargs
    assert_sexp('def x(y: 1); end')
    assert_sexp('def x(y:); end')
  end

  def test_defn_rest
    assert_sexp('def x(*args); end')
    assert_sexp('def x(**args); end')
    assert_sexp('def x(*); end')
    assert_sexp('def x(**); end')
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

  def test_simple_command
    assert_sexp('`hello`')
  end

  def test_command_interpolation
    assert_sexp('`a#{1}b`')
  end

  def test_simple_class
    assert_sexp('class A; end')
    assert_sexp('class A; x; end')
    assert_sexp('class A; x; y; end')
  end

  def test_some_constants
    assert_sexp('X')
    assert_sexp('::X')
    assert_sexp('X::Y')
  end

  def test_op_asgn1
    assert_sexp('a[1] &= 2')
  end

  def test_bracket_attribute_assign
    assert_sexp('a[1] ||= 2')
    assert_sexp('a[1] &&= 2')
  end

  def test_constant_assign
    assert_sexp('A = 1')
    assert_sexp('A::B = 1')
  end

  def test_simple_defs
    assert_sexp('def self.x; end')
  end

  def test_opasgn2
    assert_sexp('x.y += 1')
    assert_sexp('x&.y += 1')
  end

  def test_call_writes
    assert_sexp('x.y &&= 1')
    assert_sexp('x&.y &&= 1')
    assert_sexp('x.y ||= 1')
    assert_sexp('x&.y ||= 1')
  end

  def test_class_self
    assert_sexp('class << self; end')
  end

  def test_prism_node_coverage
    pn = Prism::Visitor.instance_methods(false).grep(/^visit_/).sort
    rpn = PrismToRubyParser::Visitor.instance_methods(false).grep(/^visit_/).sort
    diff = pn - rpn

    assert_empty diff, "#{diff.count} of #{pn.count} remaining #{rpn.count / pn.count.to_f * 100}%"
  end

  def test_constant_assign
    assert_sexp('A::B ||= 1')
    assert_sexp('A::B &&= 1')
    assert_sexp('A::B += 1')
    assert_sexp('A::B::C |= 1')
    assert_sexp('A ||= 1')
    assert_sexp('A &&= 1')
    assert_sexp('A += 1')
  end

  def test_lots_of_local_writes
    assert_sexp('x ||= 1')
    assert_sexp('x &&= 1')
    assert_sexp('x += 1')
  end

  def test_lots_of_class_variables
    assert_sexp('@@x ||= 1')
    assert_sexp('@@x &&= 1')
    assert_sexp('@@x += 1')
  end

  def test_lots_of_instance_variables
    assert_sexp('@x ||= 1')
    assert_sexp('@x &&= 1')
    assert_sexp('@x += 1')
  end

  def test_lots_of_global_variables
    assert_sexp('$x ||= 1')
    assert_sexp('$x &&= 1')
    assert_sexp('$x += 1')
  end

  def test_forwarding
    assert_sexp('def x(...); y(...); end')
  end

  def test_some_multiassigns
    assert_sexp('x, y = 1, 2')
    assert_sexp('x, y = *z')
    assert_sexp('x, = *z')
    assert_sexp('@x, @@y, Z, Y::W, $Q, * = 1,2,3,4,5')
  end

  def test_awhile
    assert_sexp('while x do; end')
    assert_sexp('while x do; y; end')
    assert_sexp('while x do; y; z; end')
    assert_sexp('begin; x; y; end while z')
  end

  def test_until
    assert_sexp('until x do; end')
    assert_sexp('until x do; y; end')
    assert_sexp('until x do; y; z; end')
    assert_sexp('begin; x; y; end until z')
  end

  def test_rescue_in_def
    assert_sexp('def x; blah; blah; rescue; y; z; end')
  end

  def test_files_and_lines
    assert_sexp('__FILE__')
    assert_sexp('__LINE__')
  end

  def test_lasgn_splat
    assert_sexp('x = *y, 1')
    assert_sexp('x = *y')
    assert_sexp('x = *[y]')
  end

  def test_simple_match
    assert_sexp('[0, 1] => _, x')
    assert_sexp('{y: 2} => y: z')
  end

  def test_interpolated_strings_and_things
    assert_sexp('"#{""}"')
    assert_sexp('"#{"a"}#{"b"}"')
    assert_sexp('"a#{"b"}c#{"d"}"')
    assert_sexp('"a#{"b"}c#{"d"}e"')


    assert_sexp('`a#{"b"}c#{"d"}e`')
    assert_sexp(':"a#{"b"}c#{"d"}e"')
    assert_sexp('/a#{"b"}c#{"d"}e/')

    assert_sexp('"a#{x}"')
    assert_sexp('`a#{x}`')
    assert_sexp(':"a#{x}"')
    assert_sexp('/"a#{x}/')

    assert_sexp('"#{a} b"')

    # We go farther than RP here
    # assert_sexp(':"a#{:b}c#{:d}e"')
  end

  def test_rescue_modifier
    assert_sexp('x rescue nil')
  end

  def test_simple_pattern_predicates
    assert_sexp('{a: 1, b: 2} in {a:}')
  end

  def test_simple_case_matching
    assert_sexp("case x; in [String]; y; z; else; a; end")
    assert_sexp("w = 1; case x; in ^w; y(x); z; else; a; end")
    assert_sexp(<<~RUBY)
      case data
      in { a: Integer, **a }
        "matched"
      else
        "not matched"
      end
    RUBY
  end

  def test_simple_numbered_block_params
    assert_sexp('x { _1 }')
  end

  def test_encoding
    assert_sexp('__ENCODING__')
  end

  def test_imaginary_numbers
    assert_sexp('0b10i')
  end

  def test_rescue_rescue
    assert_sexp("begin\n rescue\n x\nrescue\n end")
  end
end
