require 'prism'

class PrismToRubyParserVisitor < Prism::Visitor
  # Helper functions

  def set_line(p_node, new_sexp)
    new_sexp.line = p_node.location.start_line
    new_sexp.max_line = p_node.location.end_line
    new_sexp
  end

  # Create Sexp with given type, set line based
  # on Prism node, and append the rest of the arguments
  def m(p_node, type, *)
    raise 'Pass Prism node as first argument' unless p_node.is_a? Prism::Node

    Sexp.new(type, *).tap do |n|
      yield n if block_given?

      set_line(p_node, n)
    end
  end

  # Create a new Sexp and concat the last argument to it.
  #
  # This is generally better than splatting the last argument,
  # especially if the last argument is long.
  def m_c(p_node, type, *, concat_arg)
    raise 'Pass Prism node as first argument' unless p_node.is_a? Prism::Node

    m(p_node, type, *) do |n|
      if concat_arg # might be nil
        n.concat(concat_arg)
      end
    end
  end

  def m_with_splat_args(node, type, node_args)
    m(node, type) do |n|
      if node_args
        args = visit(node_args)

        if args.any? { |a| a.sexp_type == :splat }
          n << m_c(node, :svalue, args)
        else
          n.concat args
        end
      end
    end

  end

  def map_visit(node_array)
    node_array.map { |n| visit(n) }
  end

  # Structure nodes

  def visit_program_node(node)
    visit(node.statements)
  end

  def visit_statements_node(node, bare: false)
    if node.body.length > 1
      if bare
        map_visit(node.body)
      else
        m(node, :block) do |n|
          n.concat(map_visit(node.body))
        end
      end
    else
      if bare
        [visit(node.body.first)]
      else
        # ruby_parser does not set a root Sexp
        # when there is only one
        visit(node.body.first)
      end
    end
  end

  def visit_parentheses_node(node)
    visit(node.body)
  end

  # Calls and attribute assignments

  def visit_call_node(node)
    type = case
           when node.attribute_write? && node.safe_navigation?
             :safe_attrasgn
           when node.attribute_write?
             :attrasgn
           when node.safe_navigation?
             :safe_call
           else
             :call
           end

    call = m_c(node, type, visit(node.receiver), node.name, visit(node.arguments))

    if node.block
      if node.block.is_a? Prism::BlockNode
        call_node_with_block(call, node)
      else
        call << visit(node.block)
      end
    else
      call
    end
  end

  def visit_super_node(node)
    m_c(node, :super, visit(node.arguments)).tap do |n|
      n << visit(node.block) if node.block
    end
  end

  def visit_forwarding_super_node(node)
    m(node, :zsuper)
  end

  # E.g. `a[1] += 1`
  def visit_index_operator_write_node(node)
    arglist = m_c(node.arguments, :arglist, visit(node.arguments))

    m(node,
      :op_asgn1,
      visit(node.receiver),
      arglist,
      node.operator,
      visit(node.value))
  end

  # Helper for visit_call_node
  def call_node_with_block(call, node)
    m(node, :iter, call) do |n|
      if node.block.parameters
        n << visit(node.block.parameters)
      else
        n << 0 # ?? RP oddity indicating no block parameters
      end

      if node.block.body
        n << visit(node.block)
      end
    end
  end

  def visit_block_node(node)
    visit(node.body)
  end

  def visit_block_parameters_node(node)
    visit(node.parameters)
  end

  def visit_block_argument_node(node)
    m(node, :block_pass, visit(node.expression))
  end

  def visit_arguments_node(node)
    # Return array of arguments - ruby_parser does not have a node type
    # for method arguments
    map_visit(node.arguments)
  end

  def visit_keyword_hash_node(node)
    visit_hash_node(node)
  end

  def visit_constant_read_node(node)
    m(node, :const, node.name)
  end

  def visit_constant_path_node(node)
    if node.parent.nil?
      # ::X
      m(node, :colon3, node.child.name)
    elsif node.child.is_a? Prism::ConstantReadNode
      # X::Y
      m(node, :colon2, visit(node.parent), node.child.name)
    else
      # X::Y::Z...
      m(node, :colon2, visit(node.parent), visit(node.child))
    end
  end

  def visit_integer_node(node)
    m(node, :lit, node.value)
  end

  def visit_float_node(node)
    m(node, :lit, node.value)
  end

  def visit_symbol_node(node)
    m(node, :lit, node.unescaped.to_sym)
  end

  def visit_range_node(node)
    left = node.left && visit(node.left)
    right = node.right && visit(node.right)

    # RP will convert range nodes with integers _on both ends_
    # to a literal range
    # Copying logic straight from RP
    if left and right and left.sexp_type == :lit and right.sexp_type == :lit and Integer === left.last and Integer === right.last

      if node.exclude_end?
        m(node, :lit, (left.last...right.last))
      else
        m(node, :lit, (left.last..right.last))
      end
    else
      if node.exclude_end?
        m(node, :dot3, left, right)
      else
        m(node, :dot2, left, right)
      end
    end
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

  def visit_nil_node(node)
    m(node, :nil)
  end

  def visit_array_node(node)
    m_c(node, :array, map_visit(node.elements))
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
        n.concat(visit_statements_node(node.body, bare: true))
      else
        n << m(node, :nil)
      end
    end
  end

  def visit_parameters_node(node)
    # TODO: Add other types of parameters
    m(node, :args) do |n|
      n.concat map_visit(node.requireds) # Regular arguments
      n.concat map_visit(node.optionals) # Regular optional arguments?
      n.concat map_visit(node.keywords)  # Keyword arguments
      n << visit(node.rest) if node.rest # The rest
      n << visit(node.keyword_rest) if node.keyword_rest
      n << visit(node.block) if node.block # Block argument
      n.concat map_visit(node.posts)     # Regular arguments, but later?
    end
  end

  def visit_required_parameter_node(node)
    node.name
  end

  def visit_optional_parameter_node(node)
    m(node, :lasgn, node.name, visit(node.value))
  end

  def visit_rest_parameter_node(node)
    :"*#{node.name}" # RP oddity
  end

  def visit_required_keyword_parameter_node(node)
    m(node, :kwarg, node.name)
  end

  def visit_optional_keyword_parameter_node(node)
    m(node, :kwarg, node.name, visit(node.value))
  end

  def visit_keyword_rest_parameter_node(node)
    :"**#{node.name}" # RP oddity
  end

  def visit_block_parameter_node(node)
    :"&#{node.name}"
  end

  def visit_return_node(node)
    if node.arguments.arguments.length > 1
      args = m_c(node, :array, visit(node.arguments))
      m(node, :return, args)
    else
      m_c(node, :return, visit(node.arguments))
    end
  end

  def visit_break_node(node)
    m_with_splat_args(node, :break, node.arguments)
  end

  def visit_next_node(node)
    m_with_splat_args(node, :next, node.arguments)
  end

  def visit_yield_node(node)
    m_c(node, :yield, visit(node.arguments))
  end

  def visit_redo_node(node)
    m(node, :redo)
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

  def visit_unless_node(node)
    condition = visit(node.predicate)

    then_clause = visit(node.statements)
    else_clause = visit(node.consequent)

    m(node, :if, condition, else_clause, then_clause)
  end

  # Strings

  def visit_string_node(node)
    m(node, :str, node.unescaped)
  end

  def visit_x_string_node(node)
    m(node, :xstr, node.unescaped)
  end

  def visit_interpolated_string_node(node)
    type = case node
           when Prism::InterpolatedStringNode
             :dstr
           when Prism::InterpolatedXStringNode
             :dxstr
           else
             raise "Unexpected type: #{node.class}"
           end

    m(node, type) do |n|
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

  def visit_interpolated_x_string_node(node)
    visit_interpolated_string_node(node)
  end

  def visit_embedded_statements_node(node)
    m(node, :evstr) do |n|
      n << visit(node.statements)
    end
  end

  def visit_embedded_variable_node(node)
    m(node, :evstr, visit(node.variable))
  end

  # Classes and such

  def visit_class_node(node)
    name = if node.constant_path.is_a? Prism::ConstantReadNode
             node.constant_path.name
           else
             visit(node.constant_path)
           end

    m(node, :class, name) do |n|
      if node.superclass
        n << visit(node.superclass)
      else
        # RP uses nil for no superclass
        n << nil
      end

      if node.body
        # Do _not_ wrap in :block
        n.concat visit_statements_node(node.body, bare: true)
      end
    end
  end

  def visit_module_node(node)
    name = if node.constant_path.is_a? Prism::ConstantReadNode
             node.constant_path.name
           else
             visit(node.constant_path)
           end

    m_c(node, :module, name, visit_statements_node(node.body, bare: true))
  end

  def visit_instance_variable_read_node(node)
    m(node, :ivar, node.name)
  end

  def visit_instance_variable_write_node(node)
    m(node, :iasgn, node.name, visit(node.value))
  end

  # @a ||= foo
  def visit_instance_variable_or_write_node(node)
    m(node, :op_asgn_or,
        m(node, :ivar, node.name),
        m(node, :iasgn, node.name, visit(node.value)))
  end

  def visit_class_variable_read_node(node)
    m(node, :cvar, node.name)
  end

  def visit_class_variable_write_node(node)
    m(node, :cvdecl, node.name, visit(node.value))
  end
end
