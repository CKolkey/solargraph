require 'set'

module Solargraph
  class ApiMap
    class Store
      # @return [Array<Solargraph::Pin::Base>]
      attr_reader :pins

      # @param pins [Array<Solargraph::Pin::Base>]
      def initialize pins = []
        @pins = pins
        index
      end

      # @param fqns [String]
      # @param visibility [Array<Symbol>]
      # @return [Array<Solargraph::Pin::Base>]
      def get_constants fqns, visibility = [:public]
        namespace_children(fqns).select { |pin|
          !pin.name.empty? and (pin.kind == Pin::NAMESPACE or pin.kind == Pin::CONSTANT) and visibility.include?(pin.visibility)
        }
      end

      # @param fqns [String]
      # @param scope [Symbol]
      # @param visibility [Array<Symbol>]
      # @return [Array<Solargraph::Pin::Base>]
      def get_methods fqns, scope: :instance, visibility: [:public]
        kinds = [Pin::METHOD, Pin::ATTRIBUTE, Pin::METHOD_ALIAS]
        namespace_children(fqns).select do |pin|
          kinds.include?(pin.kind) && pin.scope == scope && visibility.include?(pin.visibility)
        end
      end

      # @param fqns [String]
      # @return [String]
      def get_superclass fqns
        return superclass_references[fqns].first if superclass_references.key?(fqns)
        nil
      end

      # @param fqns [String]
      # @return [Array<String>]
      def get_includes fqns
        include_references[fqns] || []
      end

      # @param fqns [String]
      # @return [Array<String>]
      def get_extends fqns
        extend_references[fqns] || []
      end

      # @param path [String]
      # @return [Array<Solargraph::Pin::Base>]
      def get_path_pins path
        path_pin_hash[path] || []
      end

      # @param fqns [String]
      # @param scope [Symbol] :class or :instance
      # @return [Array<Solargraph::Pin::Base>]
      def get_instance_variables(fqns, scope = :instance)
        # namespace_children(fqns).select{|pin| pin.kind == Pin::INSTANCE_VARIABLE and pin.context.scope == scope}
        all_instance_variables.select { |pin|
          pin.binder.namespace == fqns && pin.binder.scope == scope
        }
      end

      # @param fqns [String]
      # @return [Array<Solargraph::Pin::Base>]
      def get_class_variables(fqns)
        namespace_children(fqns).select{|pin| pin.kind == Pin::CLASS_VARIABLE}
      end

      # @return [Array<Solargraph::Pin::Base>]
      def get_symbols
        symbols.uniq(&:name)
      end

      # @param fqns [String]
      # @return [Boolean]
      def namespace_exists?(fqns)
        fqns_pins(fqns).any?
      end

      # @return [Set<String>]
      def namespaces
        @namespaces ||= Set.new
      end

      # @return [Array<Solargraph::Pin::Base>]
      def namespace_pins
        # @namespace_pins ||= pins.select{|p| p.kind == Pin::NAMESPACE}
        @namespace_pins ||= []
      end

      # @return [Array<Solargraph::Pin::Base>]
      def method_pins
        # @method_pins ||= pins.select{|p| p.kind == Pin::METHOD or p.kind == Pin::ATTRIBUTE}
        @method_pins ||= []
      end

      # @param fqns [String]
      # @return [Array<String>]
      def domains(fqns)
        result = []
        fqns_pins(fqns).each do |nspin|
          result.concat nspin.domains
        end
        result
      end

      # @return [Hash]
      def named_macros
        @named_macros ||= begin
          result = {}
          pins.each do |pin|
            pin.macros.select{|m| m.tag.tag_name == 'macro'}.each do |macro|
              next if macro.tag.name.nil? || macro.tag.name.empty?
              result[macro.tag.name] = macro
            end
          end
          result
        end
      end

      # @return [Array<Pin::Block>]
      def block_pins
        @block_pins ||= []
      end

      def inspect
        # Avoid insane dumps in specs
        to_s
      end

      private

      # @param fqns [String]
      # @return [Array<Solargraph::Pin::Namespace>]
      def fqns_pins fqns
        return [] if fqns.nil?
        if fqns.include?('::')
          parts = fqns.split('::')
          name = parts.pop
          base = parts.join('::')
        else
          base = ''
          name = fqns
        end
        namespace_children(base).select{|pin| pin.name == name and pin.kind == Pin::NAMESPACE}
      end

      # @return [Array<Solargraph::Pin::Symbol>]
      def symbols
        @symbols ||= []
      end

      def superclass_references
        @superclass_references ||= {}
      end

      def include_references
        @include_references ||= {}
      end

      def extend_references
        @extend_references ||= {}
      end

      # @param name [String]
      # @return [Array<Solargraph::Pin::Base>]
      def namespace_children name
        namespace_map[name] || []
      end

      # @return [Hash]
      def namespace_map
        @namespace_map ||= {}
      end

      def all_instance_variables
        @all_instance_variables ||= []
      end

      def path_pin_hash
        @path_pin_hash ||= {}
      end

      # @return [void]
      def index
        namespace_map.clear
        namespaces.clear
        namespace_pins.clear
        method_pins.clear
        symbols.clear
        block_pins.clear
        all_instance_variables.clear
        path_pin_hash.clear
        namespace_map[''] = []
        override_pins = []
        pins.each do |pin|
          namespace_map[pin.namespace] ||= []
          namespace_map[pin.namespace].push pin
          namespaces.add pin.path if pin.kind == Pin::NAMESPACE and !pin.path.empty?
          namespace_pins.push pin if pin.kind == Pin::NAMESPACE
          method_pins.push pin if pin.kind == Pin::METHOD || pin.kind == Pin::ATTRIBUTE
          symbols.push pin if pin.kind == Pin::SYMBOL
          if pin.kind == Pin::INCLUDE_REFERENCE
            include_references[pin.namespace] ||= []
            include_references[pin.namespace].push pin.name
          elsif pin.kind == Pin::EXTEND_REFERENCE
            extend_references[pin.namespace] ||= []
            extend_references[pin.namespace].push pin.name
          elsif pin.kind == Pin::SUPERCLASS_REFERENCE
            superclass_references[pin.namespace] ||= []
            superclass_references[pin.namespace].push pin.name
          elsif pin.is_a?(Pin::Block)
            block_pins.push pin
          elsif pin.is_a?(Pin::InstanceVariable)
            all_instance_variables.push pin
          elsif pin.is_a?(Pin::Reference::Override)
            override_pins.push pin
          end
          if pin.path
            path_pin_hash[pin.path] ||= []
            path_pin_hash[pin.path].push pin
          end
        end
        override_pins.each do |ovr|
          pin = get_path_pins(ovr.name).first
          next if pin.nil?
          pin.docstring.delete_tags(:overload)
          pin.docstring.delete_tags(:return)
          ovr.tags.each do |tag|
            pin.docstring.add_tag(tag)
          end
        end
      end
    end
  end
end
