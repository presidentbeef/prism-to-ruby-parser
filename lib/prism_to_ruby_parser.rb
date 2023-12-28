require 'prism'

class PrismToRubyParserVisitor < Prism::Visitor
  def set_line(p_node, new_sexp)
    new_sexp.line = p_node.location.start_line
    new_sexp.max_line = p_node.location.end_line
    new_sexp
  end

  def m(p_node, type, *)
    Sexp.new(type, *).tap do |n|
      yield n if block_given?

      set_line(p_node, n)
    end
  end

  def map_visit(node_array)
    node_array.map { |n| visit(n) }
  end

  def visit_statements_node(node)
    if node.body.length > 1
      m(node, :block) do |n|
        n.concat(map_visit(node.body))
      end
    else
      # ruby_parser does not set a root Sexp
      # when there is only one
      visit(node.body.first)
    end
  end

  def visit_program_node(node)
    visit(node.statements)
  end

  def visit_call_node(node)
    type = if node.name.match? /\w\=$/
             :attrasgn
           else
             :call
           end

    m(node, type, visit(node.receiver), node.name) do |n|
      n.concat(visit(node.arguments)) if node.arguments
    end
  end

  def visit_arguments_node(node)
    # Return array of arguments - ruby_parser does not have a node type
    # for method arguments
    map_visit(node.arguments)
  end

  def visit_integer_node(node)
    m(node, :lit, node.value)
  end

  def visit_string_node(node)
    m(node, :str, node.unescaped)
  end

  def visit_symbol_node(node)
    m(node, :lit, node.unescaped.to_sym)
  end

  def visit_local_variable_write_node(node)
    m(node, :lasgn, node.name, visit(node.value))
  end

  def visit_regular_expression_node(node)
    m(node, :lit, Regexp.new(node.unescaped))
  end
end
