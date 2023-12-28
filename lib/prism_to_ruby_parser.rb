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
    type = if node.name == :[]= or node.name.match?(/\w\=$/)
             :attrasgn
           else
             :call
           end

    call = m(node, type, visit(node.receiver), node.name) do |n|
      n.concat(visit(node.arguments)) if node.arguments
    end

    if node.block
      call_node_with_block(call, node)
    else
      call
    end
  end

  # Helper for visit_call_node
  def call_node_with_block(call, node)
    m(node, :iter, call) do |n|
      if node.block.parameters
        n << visit(node.block.parameters)
      end

      n << visit(node.block)
    end
  end

  def visit_block_node(node)
    if node.body.nil?
      [0] # RubyParser oddity
    else
      visit(node.body)
    end
  end

  def visit_block_parameters_node(node)
    visit(node.parameters)
  end

  def visit_arguments_node(node)
    # Return array of arguments - ruby_parser does not have a node type
    # for method arguments
    map_visit(node.arguments)
  end

  def visit_constant_read_node(node)
    m(node, :const, node.name)
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

  def visit_local_variable_read_node(node)
    m(node, :lvar, node.name)
  end

  def visit_local_variable_write_node(node)
    m(node, :lasgn, node.name, visit(node.value))
  end

  def visit_regular_expression_node(node)
    m(node, :lit, Regexp.new(node.unescaped))
  end

  def visit_false_node(node)
    m(node, :false)
  end

  def visit_true_node(node)
    m(node, :true)
  end

  def visit_array_node(node)
    m(node, :array) do |n|
      n.concat(map_visit(node.elements))
    end
  end

  def visit_hash_node(node)
    m(node, :hash) do |n|
      pairs = node.elements.flat_map do |e|
        [visit(e.key), visit(e.value)]
      end

      n.concat pairs
    end
  end

  # Hash table key-value
  def visit_assoc_node(node)
    [visit(node.key), visit(node.value)]
  end

  def visit_splat_node(node)
    m(node, :splat, visit(node.expression))
  end

  # a.y ||= foo
  def visit_call_or_write_node(node)
    m(node, :op_asgn, visit(node.receiver), visit(node.value), node.read_name, :'||')
  end

  # a ||= foo
  def visit_local_variable_or_write_node(node)
    m(node, :op_asgn_or,
        m(node, :lvar, node.name),
        m(node, :lasgn, node.name, visit(node.value)))
  end

  def visit_self_node(node)
    m(node, :self)
  end

  # Method definitions

  def visit_def_node(node)
    args = if node.parameters
             visit(node.parameters)
           else
             m(node, :args)
           end

    m(node, :defn, node.name, args) do |n|
      if node.body
        # body is a Statements node, but we don't want to wrap it in a :block
        # so we're grabbing the Statements body directly
        # HACK?
        n.concat(map_visit(node.body.body))
      else
        n << m(node, :nil)
      end
    end
  end

  def visit_parameters_node(node)
    # TODO: Add other types of parameters
    m(node, :args, *map_visit(node.requireds))
  end

  def visit_required_parameter_node(node)
    node.name
  end

  # Conditionals

  def visit_if_node(node)
    condition = visit(node.predicate)

    then_clause = visit(node.statements)
    else_clause = visit(node.consequent)

    m(node, :if, condition, then_clause, else_clause)
  end

  def visit_else_node(node)
    visit(node.statements)
  end

  # Strings

  def visit_interpolated_string_node(node)
    m(node, :dstr) do |n|
      node.parts.each_with_index do |part, i|
        if i == 0 # only for first part of string
          if part.is_a? Prism::StringNode
            n << part.unescaped
            next
          else
            # RP explicitly uses a bare empty string
            # if the first value is not a string
            n << ''
          end
        end

        n << visit(part)
      end
    end
  end

  def visit_embedded_statements_node(node)
    m(node, :evstr) do |n|
      n << visit(node.statements)
    end
  end

  # Classes and such

  def visit_instance_variable_read_node(node)
    m(node, :ivar, node.name)
  end

  def visit_instance_variable_write_node(node)
    m(node, :iasgn, node.name, visit(node.value))
  end
end
