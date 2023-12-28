require 'prism'

class PrismToRubyParserVisitor < Prism::Visitor
  def set_line(p_node, new_sexp)
    new_sexp.line = p_node.location.start_line
    new_sexp.max_line = p_node.location.end_line
    new_sexp
  end

  def visit_program_node(node)
    if node.statements.body.length > 1
      Sexp.new(:block).tap do |n|
        n.concat(visit_all(node.statements))
        set_line(node, n)
      end
    else
      visit(node.statements.body.first)
    end
  end

  def visit_call_node(node)
    Sexp.new(:call, visit(node.receiver), node.name).tap do |n|
      n.concat(visit_all(node.arguments)) if node.arguments
      set_line(node, n)
    end
  end

  end
end
