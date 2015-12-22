require 'active_support/concern'

module OrigenTesters
  # Include this module in any class you define as a test interface
  module Interface
    extend ActiveSupport::Concern

    included do
      Origen.add_interface(self)

      (ATP::AST::Builder::CONDITION_KEYS + [:group]).each do |method|
        define_method method do |*args, &block|
          flow.send(method, *args, &block)
        end
      end
    end

    # This identifier will be used to make labels and other references unique to the
    # current application. This will help to avoid name duplication if a program is
    # comprised of many modules generated by Origen.
    #
    # Override in the application interface to customize, by default the identifier
    # will be Origen.config.initials
    def app_identifier
      Origen.config.initials || 'Anon App'
    end

    def close(options = {})
      sheet_generators.each do |generator|
        generator.close(options)
      end
    end

    # Compile a template file
    def compile(file, options = {})
      # Any options passed in from an interface will be passed to the compiler and to
      # the templates being compiled
      options[:initial_options] = options
      Origen.file_handler.preserve_state do
        begin
          file = Origen.file_handler.clean_path_to_template(file)
          Origen.generator.compile_file_or_directory(file, options)
        rescue
          file = Origen.file_handler.clean_path_to(file)
          Origen.generator.compile_file_or_directory(file, options)
        end
      end
    end

    def import(file, options = {})
      # Attach the import request to the first generator, when it imports
      # it any generated resources will automatically find their way to the
      # correct generator/collection
      generator = flow || sheet_generators.first
      generator.import(file, options)
    end

    def render(file, options = {})
      if sheet_generators.size > 1
        fail "You must specify which generator to render content to! e.g.  i.test_instances.render '#{file}'"
      else
        sheet_generators.first.render(file, options)
      end
    end

    def write_files(options = {})
      sheet_generators.each do |generator|
        generator.finalize(options)
      end
      sheet_generators.each do |generator|
        generator.write_to_file(options) if generator.to_be_written?
      end
      clean_referenced_patterns
      reset_globals
    end

    # All generators should push to this array whenever they reference a pattern
    # so that it is captured in the pattern list, e.g.
    #   Origen.interface.referenced_patterns << pattern
    def referenced_patterns
      @@referenced_patterns ||= []
    end

    # All generators should push to this array whenever they reference a subroutine
    # pattern so that it is captured in the pattern list, e.g.
    #   Origen.interface.referenced_subroutine_patterns << pattern
    def referenced_subroutine_patterns
      unless Origen.tester.v93k?
        fail 'referenced_subroutine_patterns is currently only implemented for V93k!'
      end
      @@referenced_subroutine_patterns ||= []
    end

    # Remove duplicates and file extensions from the referenced pattern lists
    def clean_referenced_patterns
      refs = [:referenced_patterns]
      refs << :referenced_subroutine_patterns if Origen.tester.v93k?
      refs.each do |ref|
        ref = send(ref)
        ref.uniq!
        ref.map! do |pat|
          pat.sub(/\..*/, '')
        end
        ref.uniq!
      end
    end

    # Add a comment line into the buffer
    def comment(text)
      comments << text
    end

    def comments
      @@comments ||= []
    end

    def discard_comments
      @@comments = nil
    end

    # Returns the buffered description comments and clears the buffer
    def consume_comments
      c = comments
      discard_comments
      c
    end

    def top_level_flow
      @@top_level_flow ||= nil
    end
    alias_method :top_level_flow_filename, :top_level_flow

    def flow_generator
      flow
    end

    def set_top_level_flow
      @@top_level_flow = flow_generator.output_file
    end

    def clear_top_level_flow
      @@top_level_flow = nil
    end

    # A storage Hash that all generators can push comment descriptions
    # into when generating.
    # At the end of a generation run this will contain all descriptions
    # for all flows that were just created.
    #
    # Access via Origen.interface.descriptions
    def descriptions
      @@descriptions ||= Parser::DescriptionLookup.new
    end

    # Any tests generated within the given block will be generated in resources mode.
    # Generally this means that all resources for a given test will be generated but
    # flow entries will be inhibited.
    def resources_mode
      orig = @resources_mode
      @resources_mode = true
      yield
      @resources_mode = orig
    end

    def resources_mode?
      @resources_mode
    end

    def identity_map # :nodoc:
      @@identity_map ||= ::OrigenTesters::Generator::IdentityMap.new
    end

    def platform
      # This branch to support the ProgramGenerators module where the generator
      # is included into an interface instance and not the class
      if singleton_class.const_defined? :PLATFORM
        singleton_class::PLATFORM
      else
        self.class::PLATFORM
      end
    end

    module ClassMethods
      # Returns true if the interface class supports the
      # given tester instance
      def supports?(tester_instance)
        tester_instance.class == self::PLATFORM
      end
    end
  end
end
