require 'sexp_processor'

module PrismToRubyParser
  class Visitor < Prism::BasicVisitor
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

    def sexp_type?(sexp, type)
      sexp.is_a? Sexp and
        sexp.sexp_type == type
    end

    def set_value(sexp, value)
      raise unless sexp.is_a? Sexp and sexp.length == 2

      sexp[1] = value
    end

    # Structure nodes

    def visit_program_node(node)
      visit(node.statements)
    end

    def visit_statements_node(node, bare: false)
      return nil if node.nil?

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
      if node.body
        visit(node.body)
      else
        # ()
        m(node, :nil)
      end
    end

    def visit_begin_node(node)
      result = if node.statements.nil?
                 m(node, :nil)
               else
                 visit(node.statements)
               end

      if node.rescue_clause
        if node.statements
          result = m(node.rescue_clause, :rescue, result, visit(node.rescue_clause))
        else
          result = m(node.rescue_clause, :rescue, visit(node.rescue_clause))
        end
      end

      if node.ensure_clause
        result = m(node.ensure_clause, :ensure, result, visit(node.ensure_clause))
      end

      result
    end

    def visit_rescue_node(node)
      exceptions = m_c(node, :array, map_visit(node.exceptions))

      statements = if node.statements
                     visit(node.statements)
                   else
                     nil
                   end

      m(node, :resbody, exceptions, statements)
    end

    def visit_rescue_modifier_node(node)
      resbody = m(node,
                  :resbody,
                  m(node, :array),
                  visit(node.rescue_expression))

      m(node, :rescue, visit(node.expression), resbody)
    end

    def visit_ensure_node(node)
      if node.statements
        visit(node.statements)
      else
        m(node, :nil)
      end
    end

    # Calls and attribute assignments

    def visit_call_node(node)
      if node.name == :'=~' and
          (node.receiver.is_a? Prism::StringNode or
           node.receiver.is_a? Prism::RegularExpressionNode)

      # RP special cases
      # /x/ =~ 'y'
      # 'y' =~ /x/
      return make_match_node(node)
      end

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

=begin
 @source="x[1] ||= 1"
 @value=
  @ ProgramNode (location: (1,0)-(1,10))
  ├── locals: []
  └── statements:
      @ StatementsNode (location: (1,0)-(1,10))
      └── body: (length: 1)
          └── @ IndexOrWriteNode (location: (1,0)-(1,10))
              ├── flags: ∅
              ├── receiver:
              │   @ CallNode (location: (1,0)-(1,1))
              │   ├── flags: variable_call
              │   ├── receiver: ∅
              │   ├── call_operator_loc: ∅
              │   ├── name: :x
              │   ├── message_loc: (1,0)-(1,1) = "x"
              │   ├── opening_loc: ∅
              │   ├── arguments: ∅
              │   ├── closing_loc: ∅
              │   └── block: ∅
              ├── call_operator_loc: ∅
              ├── opening_loc: (1,1)-(1,2) = "["
              ├── arguments:
              │   @ ArgumentsNode (location: (1,2)-(1,3))
              │   ├── flags: ∅
              │   └── arguments: (length: 1)
              │       └── @ IntegerNode (location: (1,2)-(1,3))
              │           └── flags: decimal
              ├── closing_loc: (1,3)-(1,4) = "]"
              ├── block: ∅
              ├── operator_loc: (1,5)-(1,8) = "||="
              └── value:
                  @ IntegerNode (location: (1,9)-(1,10))
                  └── flags: decimal,
=end
    def visit_index_or_write_node(node)
      bracket_args = m_c(node, :arglist, visit(node.arguments))
      m(node, :op_asgn1, visit(node.receiver), bracket_args, :'||', visit(node.value))
    end

    def visit_index_and_write_node(node)
      bracket_args = m_c(node, :arglist, visit(node.arguments))
      m(node, :op_asgn1, visit(node.receiver), bracket_args, :'&&', visit(node.value))
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

    def make_match_node(node)
      if node.receiver.is_a? Prism::StringNode
        m(node, :match3, visit(node.arguments).first, visit(node.receiver))
      elsif node.receiver.is_a? Prism::RegularExpressionNode
        m(node, :match2, visit(node.receiver), visit(node.arguments).first)
      else
        raise "Unexpected values for match node: #{node.inspect}"
      end
    end

    def visit_lambda_node(node)
      m(node, :iter, m(node, :lambda)) do |n|
        if node.parameters
          if node.parameters.parameters.nil?
            n << m(node.parameters, :args)
          else
            n << visit(node.parameters)
          end
        else
          n << 0
        end

        if node.body
          n << visit(node.body)
        end
      end
    end

    def visit_block_node(node)
      visit(node.body)
    end

    def visit_block_parameters_node(node)
      # Explicitly local block variables
      shadows = if node.locals.any?
                  m_c(node, :shadow, map_visit(node.locals))
                else
                  nil
                end

      if node.parameters
        visit(node.parameters).tap do |params|
          params << shadows if shadows
        end
      elsif shadows # only shadowed params
        m(node, :args, shadows)
      else
        m(node, :args)
      end
    end

    def visit_block_argument_node(node)
      m(node, :block_pass, visit(node.expression))
    end

    def visit_block_local_variable_node(node)
      node.name
    end

    def visit_forwarding_arguments_node(node)
      m(node, :forward_args)
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

    def visit_constant_write_node(node)
      m(node, :cdecl, node.name, visit(node.value))
    end

    def visit_constant_or_write_node(node)
      m(node, :op_asgn_or, m(node, :const, node.name), m(node, :cdecl, node.name, visit(node.value)))
    end

    def visit_constant_and_write_node(node)
      m(node, :op_asgn_and, m(node, :const, node.name), m(node, :cdecl, node.name, visit(node.value)))
    end

    def visit_constant_operator_write_node(node)
      m(node,
        :cdecl,
        node.name,
        m(node,
          :call,
          m(node, :const, node.name),
          node.operator,
          visit(node.value)))
    end

    def visit_constant_path_write_node(node)
      m(node, :cdecl, visit(node.target), visit(node.value))
    end

    def visit_constant_path_or_write_node(node)
      m(node, :op_asgn_or, visit(node.target), visit(node.value))
    end

    def visit_constant_path_and_write_node(node)
      m(node, :op_asgn_and, visit(node.target), visit(node.value))
    end

    def visit_constant_path_operator_write_node(node)
      m(node, :op_asgn, visit(node.target), node.operator, visit(node.value))
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

    def visit_regular_expression_node(node)
      flags = 0

      flags |= Regexp::MULTILINE if node.multi_line?
      flags |= Regexp::IGNORECASE if node.ignore_case?
      flags |= Regexp::EXTENDED if node.extended?
      flags |= Regexp::ENC_NONE if node.ascii_8bit?

      m(node, :lit, Regexp.new(node.unescaped, flags))
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
      value = visit(node.value)

      if node.value.is_a? Prism::ArrayNode and node.value.contains_splat?
        if node.value.elements.length == 1
          value = value.last
        end

        value = m(node, :svalue, value)
      end

      m(node, :lasgn, node.name, value)
    end

    def visit_local_variable_and_write_node(node)
      # Is this being too clever?
      m(node, :op_asgn_and,
        visit_local_variable_read_node(node),
        visit_local_variable_write_node(node))
    end

    def visit_local_variable_operator_write_node(node)
      m(node, :lasgn, node.name,
        m(node, :call, m(node, :lvar, node.name), node.operator, visit(node.value)))
    end

    def visit_global_variable_read_node(node)
      m(node, :gvar, node.name)
    end

    def visit_global_variable_write_node(node)
      m(node, :gasgn, node.name, visit(node.value))
    end


    def visit_global_variable_and_write_node(node)
      m(node, :op_asgn_and,
        visit_global_variable_read_node(node),
        visit_global_variable_write_node(node))
    end

    def visit_global_variable_or_write_node(node)
      m(node, :op_asgn_or,
        visit_global_variable_read_node(node),
        visit_global_variable_write_node(node))
    end

    def visit_global_variable_operator_write_node(node)
      m(node, :gasgn, node.name,
        m(node, :call, m(node, :gvar, node.name), node.operator, visit(node.value)))
    end

    def visit_alias_global_variable_node(node)
      m(node, :valias, node.new_name.name, node.old_name.name)
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
          visit(e)
        end

        n.concat pairs
      end
    end

    # Hash table key-value
    def visit_assoc_node(node)
      [visit(node.key), visit(node.value)]
    end

    # { x: }
    def visit_implicit_node(node)
      nil
    end

    def visit_splat_node(node)
      if node.expression
        m(node, :splat, visit(node.expression))
      else
        # Sometimes there are bare splats, like in
        # parallel assignment:
        # x, * = 1, 2, 3
        m(node, :splat)
      end
    end

    def visit_assoc_splat_node(node)
      if node.value
        [m(node, :kwsplat, visit(node.value))]
      else
        [m(node, :kwsplat)]
      end
    end

    # a.y ||= foo
    def visit_call_or_write_node(node)
      type = if node.safe_navigation? # a&.y ||= foo
               :safe_op_asgn2
             else
               :op_asgn2
             end

      m(node, type, visit(node.receiver), node.write_name, :'||', visit(node.value))
    end

    # a.y &&= foo
    def visit_call_and_write_node(node)
      type = if node.safe_navigation? # a&.y ||= foo
               :safe_op_asgn2
             else
               :op_asgn2
             end

      m(node, type, visit(node.receiver), node.write_name, :'&&', visit(node.value))
    end

    # x.y += 1
    def visit_call_operator_write_node(node)
      type = if node.safe_navigation? # a&.y ||= foo
               :safe_op_asgn2
             else
               :op_asgn2
             end

      m(node, type, visit(node.receiver), node.write_name, node.operator, visit(node.value))
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

      result = if node.receiver
                 m(node, :defs, visit(node.receiver), node.name, args)
               else
                 m(node, :defn, node.name, args)
               end

      if node.body
        @in_def = true

        if node.body.is_a? Prism::StatementsNode
          result.concat(visit_statements_node(node.body, bare: true))
        else
          result << visit(node.body)
        end

        @in_def = false
      else
        result << m(node, :nil)
      end

      result
    end

    def visit_parameters_node(node)
      # TODO: Add other types of parameters?
      m(node, :args) do |n|
        @in_parameters = true # Ugh HACK because :masgns are different in parameters

        n.concat map_visit(node.requireds) # Regular arguments
        n.concat map_visit(node.optionals) # Regular optional arguments?
        n.concat map_visit(node.keywords)  # Keyword arguments
        n << visit(node.rest) if node.rest # The rest
        n << visit(node.keyword_rest) if node.keyword_rest
        n.concat map_visit(node.posts)     # Regular arguments, but later?
        n << visit(node.block) if node.block # Block argument

        @in_parameters = false
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

    # lambda { |a, | }
    def visit_implicit_rest_node(node)
      nil # This is how RP does it
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

    def visit_forwarding_parameter_node(node)
      m(node, :forward_args)
    end

    def visit_return_node(node)
      if node.arguments.nil?
        m(node, :return)
      elsif node.arguments.arguments.length > 1
        args = m_c(node, :array, visit(node.arguments))
        m(node, :return, args)
      else
        m_with_splat_args(node, :return, node.arguments)
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

    def visit_retry_node(node)
      m(node, :retry)
    end

    def visit_alias_method_node(node)
      m(node, :alias, visit(node.new_name), visit(node.old_name))
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

    def visit_while_node(node)
      flag = !node.begin_modifier? # Flag is backwards between Prism<->RP

      m(node, :while, visit(node.predicate), visit(node.statements), flag)
    end

    def visit_until_node(node)
      flag = !node.begin_modifier? # Flag is backwards between Prism<->RP

      m(node, :until, visit(node.predicate), visit(node.statements), flag)
    end

    def visit_for_node(node)
      m(node, :for, visit(node.collection), visit(node.index)) do |n|
        n << visit(node.statements) if node.statements
      end
    end

    # Case / pattern matching

    def visit_case_node(node)
      predicate = visit(node.predicate)
      conditions = map_visit(node.conditions)
      else_clause = visit(node.consequent)

      m_c(node, :case, predicate, conditions) << else_clause
    end

    def visit_when_node(node)
      conditions = m_c(node, :array, map_visit(node.conditions))

      if node.statements
        m_c(node, :when, conditions, visit_statements_node(node.statements, bare: true))
      else
        m(node, :when, conditions, nil)
      end
    end

    def visit_match_predicate_node(node)
      predicate = visit(node.value)
      pattern = visit(node.pattern)
      else_clause = nil
      in_guard = nil # Not 100% sure this is what this is

      m(node, :case, predicate, m(node, :in, pattern, in_guard), else_clause)
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
             when Prism::InterpolatedSymbolNode
               :dsym
             when Prism::InterpolatedRegularExpressionNode
               :dregx
             else
               raise "Unexpected type: #{node.class}"
             end

      parts = []

      node.parts.each_with_index do |part, i|
        if i == 0 # only for first part of string
          if part.is_a? Prism::StringNode
            parts << part.unescaped
            next
          else
            # RP explicitly uses a bare empty string
            # if the first value is not a string
            parts << ''
          end
        end

        str = visit(part)

        if sexp_type?(str, :str)
          if sexp_type?(parts.last, :str)
            set_value(parts.last, "#{parts.last.value}#{str.value}")
          elsif parts.last.is_a? String
            parts.last << str.value
          else
            parts << str
          end
        else
          parts << str
        end
      end

      # RP simplifies interpolation if the values are simple strings
      # e.g. "#{'a"}" -> s(:str, 'a')
      if parts.length == 2 and parts.first.is_a? String and sexp_type?(parts.last, :str)
        case node
        when Prism::InterpolatedStringNode
          m(node, :str, "#{parts.first}#{parts.last.value}")
        when Prism::InterpolatedXStringNode
          m(node, :xstr, "#{parts.first}#{parts.last.value}")
        when Prism::InterpolatedSymbolNode
          m(node, :lit, :"#{parts.first}#{parts.last.value}")
        when Prism::InterpolatedRegularExpressionNode
          m(node, :lit, /#{parts.first}#{parts.last.value}/)
        end
      elsif parts in [String]
        # e.g. s(:dstr, '') -> s(:str, '')

        case node
        when Prism::InterpolatedStringNode
          m(node, :str, parts.first)
        when Prism::InterpolatedXStringNode
          m(node, :xstr, parts.first)
        when Prism::InterpolatedSymbolNode
          m(node, :lit, parts.first.to_sym)
        when Prism::InterpolatedRegularExpressionNode
          m(node, :lit, /#{parts.first}/)
        end
      else
        m_c(node, type, parts)
      end
    end

    def visit_interpolated_x_string_node(node)
      visit_interpolated_string_node(node)
    end

    def visit_interpolated_regular_expression_node(node)
      result = visit_interpolated_string_node(node)

      flags = 0

      flags |= Regexp::MULTILINE if node.multi_line?
      flags |= Regexp::IGNORECASE if node.ignore_case?
      flags |= Regexp::EXTENDED if node.extended?
      flags |= Regexp::ENC_NONE if node.ascii_8bit?

      if flags != 0
        result << flags
      end

      if node.once?
        result.sexp_type = :dregx_once
      end

      result
    end

    def visit_interpolated_symbol_node(node)
      visit_interpolated_string_node(node)
    end

    def visit_embedded_statements_node(node)
      result = m(node, :evstr) do |n|
        n << visit(node.statements) if node.statements
      end

      # s(:evstr, s(:str, '...'))
      if result.length == 2 and sexp_type?(result.last, :str)
        result.last
      else
        result
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

      if node.body
        m_c(node, :module, name, visit_statements_node(node.body, bare: true))
      else
        m(node, :module, name)
      end
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

    def visit_instance_variable_and_write_node(node)
      m(node, :op_asgn_and,
        m(node, :ivar, node.name),
        m(node, :iasgn, node.name, visit(node.value)))
    end

    def visit_instance_variable_operator_write_node(node)
      m(node, :iasgn, node.name,
        m(node, :call, m(node, :ivar, node.name), node.operator, visit(node.value)))
    end

    def visit_class_variable_read_node(node)
      m(node, :cvar, node.name)
    end

    def visit_class_variable_write_node(node)
      if @in_def # :(
        m(node, :cvasgn, node.name, visit(node.value))
      else
        m(node, :cvdecl, node.name, visit(node.value))
      end
    end

    def visit_class_variable_and_write_node(node)
      m(node, :op_asgn_and,
        visit_class_variable_read_node(node),
        visit_class_variable_write_node(node))
    end

    def visit_class_variable_or_write_node(node)
      m(node, :op_asgn_or,
        visit_class_variable_read_node(node),
        visit_class_variable_write_node(node))
    end

    def visit_class_variable_operator_write_node(node)
      m(node, :cvdecl, node.name,
        m(node, :call, m(node, :cvar, node.name), node.operator, visit(node.value)))
    end

    # class << self
    def visit_singleton_class_node(node)
      if node.body
        m_c(node, :sclass, visit(node.expression), visit_statements_node(node.body, bare: true))
      else
        m(node, :sclass, visit(node.expression))
      end
    end

    # Miscellaneous

    def visit_defined_node(node)
      m(node, :defined, visit(node.value))
    end

    def visit_undef_node(node)
      if node.names.length > 1
        undefs = node.names.map do |n|
          m(n, :undef, visit(n))
        end

        m_c(node, :block, undefs)
      else
        m(node, :undef, visit(node.names.first))
      end
    end

    def visit_numbered_reference_read_node(node)
      m(node, :nth_ref, node.number)
    end

    # $', $&, $`, etc.
    def visit_back_reference_read_node(node)
      m(node, :back_ref, node.name[-1].to_sym)
    end

    # if /x/
    def visit_match_last_line_node(node)
      m(node, :match, visit_regular_expression_node(node))
    end

    def visit_source_file_node(node)
      if node.filepath == ''
        m(node, :str, '(string)')
      else
        m(node, :str, node.filepath)
      end
    end

    def visit_source_line_node(node)
      m(node, :lit, node.location.start_line)
    end

    def visit_pre_execution_node(node)
      m(node, :iter, m(node, :preexe), 0) do |n|
        n << visit(node.statements) if node.statements
      end
    end

    def visit_post_execution_node(node)
      m(node, :iter, m(node, :postexe), 0) do |n|
        n << visit(node.statements) if node.statements
      end
    end

    # Multi-assigns

    # @source="x,y = 1,2"
    # @value=
    #  @ ProgramNode (location: (1,0)-(1,9))
    #  ├── locals: [:x, :y]
    #  └── statements:
    #      @ StatementsNode (location: (1,0)-(1,9))
    #      └── body: (length: 1)
    #          └── @ MultiWriteNode (location: (1,0)-(1,9))
    #              ├── lefts: (length: 2)
    #              │   ├── @ LocalVariableTargetNode (location: (1,0)-(1,1))
    #              │   │   ├── name: :x
    #              │   │   └── depth: 0
    #              │   └── @ LocalVariableTargetNode (location: (1,2)-(1,3))
    #              │       ├── name: :y
    #              │       └── depth: 0
    #              ├── rest: ∅
    #              ├── rights: (length: 0)
    #              ├── lparen_loc: ∅
    #              ├── rparen_loc: ∅
    #              ├── operator_loc: (1,4)-(1,5) = "="
    #              └── value:
    #                  @ ArrayNode (location: (1,6)-(1,9))
    #                  ├── flags: ∅
    #                  ├── elements: (length: 2)
    #                  │   ├── @ IntegerNode (location: (1,6)-(1,7))
    #                  │   │   └── flags: decimal
    #                  │   └── @ IntegerNode (location: (1,8)-(1,9))
    #                  │       └── flags: decimal
    #                  ├── opening_loc: ∅
    #                  └── closing_loc: ∅,
    def visit_multi_write_node(node)
      left = m_c(node, :array, map_visit(node.lefts))

      # x, *y = 1, 2
      # but not
      # x, = 1, 2
      # RP does nothing for the latter
      if node.rest and not node.rest.is_a? Prism::ImplicitRestNode
        left << visit(node.rest)
      end

      if node.rights
        left.concat map_visit(node.rights)
      end

      right = case node.value
              when Prism::ArrayNode
                if node.value.elements.length == 1 and node.value.elements.first.is_a? Prism::SplatNode
                  # x, y = *a
                  # RP does not wrap the values in an array, but Prism always does
                  visit(node.value.elements.first)
                elsif node.value.opening_loc
                  # Bit of HACK
                  # Prism does not differentiate between
                  #   a, b = 1, 2
                  # and
                  #   a, b = [1, 2]
                  # But RP will wrap the array literal with :to_aray
                  # So one way to tell the difference is to check for location of `[`
                  # in the Prism result
                  m(node.value, :to_ary, visit(node.value))
                else
                  visit(node.value)
                end
              when Prism::SplatNode
                visit(node.value)
              else
                m(node, :to_ary, visit(node.value))
              end

      m(node, :masgn, left, right)
    end

    # x, y = 1, 2
    def visit_local_variable_target_node(node)
      m(node, :lasgn, node.name)
    end

    # @x, @y = 1, 2
    def visit_instance_variable_target_node(node)
      m(node, :iasgn, node.name)
    end

    # A, B = 1, 2
    def visit_constant_target_node(node)
      m(node, :cdecl, node.name)
    end

    # A::B, C::D = 1, 2
    def visit_constant_path_target_node(node)
      m(node, :const, visit_constant_path_node(node))
    end

    # a.b, c.d = 1, 2
    def visit_call_target_node(node)
      m(node, :attrasgn, visit(node.receiver), node.name)
    end

    # a[i], b[j] = b[j], a[i]
    def visit_index_target_node(node)
      m_c(node, :attrasgn, visit(node.receiver), :[]=, visit(node.arguments))
    end

    def visit_class_variable_target_node(node)
      m(node, :cvdecl, node.name)
    end

    def visit_global_variable_target_node(node)
      m(node, :gasgn, node.name)
    end

    def visit_multi_target_node(node)
      if @in_parameters
        # When there is an masgn inside a block parameter list,
        # the variables are not wrapped in an array
        m_c(node, :masgn, map_visit(node.lefts))
      else
        m(node, :masgn, m_c(node, :array, map_visit(node.lefts)))
      end
    end

    # Logical

    def visit_or_node(node)
      m(node, :or, visit(node.left), visit(node.right))
    end

    def visit_and_node(node)
      m(node, :and, visit(node.left), visit(node.right))
    end

    # Pattern Matching
    
    def visit_case_match_node(node)
      m_c(node, :case, visit(node.predicate), map_visit(node.conditions)).tap do |n|
        n << visit(node.consequent) if node.consequent
      end
    end

    def visit_in_node(node)
      m_c(node, :in, visit(node.pattern), visit_statements_node(node.statements, bare: true)) 
    end

    # x in y
    def visit_match_required_node(node)
      # Not really sure what 'nil' means here
      m(node, :case, visit(node.value), m(node, :in, visit(node.pattern), nil), nil)
    end

    def visit_array_pattern_node(node)
      # Not really sure what 'nil' means here
      m_c(node, :array_pat, nil, map_visit(node.requireds))
    end

    def visit_hash_pattern_node(node)
      # Not really sure what 'nil' means here
      m_c(node, :hash_pat, nil, map_visit(node.elements).flatten(1))
    end

    def visit_pinned_variable_node(node)
      visit(node.variable)
    end
  end
end
