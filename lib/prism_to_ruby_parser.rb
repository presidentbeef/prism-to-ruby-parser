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

  def visit_program_node(node)
    if node.statements.body.length > 1
      m(node, :block) do |n|
        n.concat(visit_all(node.statements))
      end
    else
      visit(node.statements.body.first)
    end
  end

  def visit_call_node(node)
    m(node, :call, visit(node.receiver), node.name) do |n|
      n.concat(visit_all(node.arguments)) if node.arguments
    end
  end

  def visit_integer_node(node)
    m(node, :lit, node.value)
  end
end
