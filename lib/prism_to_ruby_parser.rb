require 'prism'

class PrismToRubyParserVisitor < Prism::Visitor
  def visit_program_node(node)
    if node.statements.body.length > 1
      Sexp.new(:block).concat(visit_all(node.statements)).line(node.statements.location.start_line)
    else
      visit(node.statements.body.first)
    end
  end

  def visit_call_node(node)
    Sexp.new(:call,
                   visit(node.receiver),
                   node.name,
                   *visit(node.arguments)).line(node.location.start_line)

  end
end
