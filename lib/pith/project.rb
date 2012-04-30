require "logger"
require "pith/input"
require "pith/pathname_ext"
require "pith/reference_error"
require "set"
require "tilt"

module Pith

  class Project

    DEFAULT_IGNORE_PATTERNS = ["_*", ".git", ".gitignore", ".svn", ".sass-cache", "*~", "*.sw[op]"].to_set.freeze

    def initialize(input_dir, output_dir = nil, attributes = {})
      @input_dir = Pathname(input_dir)
      @output_dir = output_dir ? Pathname(output_dir) : (input_dir + "_out")
      @ignore_patterns = DEFAULT_IGNORE_PATTERNS.dup
      @input_map = {}
      @output_map = {}
      attributes.each do |k,v|
        send("#{k}=", v)
      end
      FileUtils.rm_rf(output_dir.to_s)
    end

    attr_reader :input_dir
    attr_reader :output_dir

    attr_reader :ignore_patterns
    attr_accessor :assume_content_negotiation
    attr_accessor :assume_directory_index

    def ignore(pattern)
      ignore_patterns << pattern
    end

    # Public: get inputs
    #
    # Returns Pith::Input objects representing the files in the input_dir.
    #
    def inputs
      @input_map.values
    end

    # Public: get outputs
    #
    # Returns Pith::Output objects representing the files in the output_dir.
    #
    def outputs
      inputs.map(&:output).compact
    end

    # Public: find an input.
    #
    # path - an path relative to input_dir
    #
    # Returns the first input whose path matches.
    # Returns nil if no match is found.
    #
    def input(path)
      @input_map[Pathname(path)]
    end

    # Public: find an output.
    #
    # path - an path relative to output_dir
    #
    # Returns the first output whose path matches.
    # Returns nil if no match is found.
    #
    def output(path)
      @output_map[Pathname(path)]
    end

    # Public: build the project, generating output files.
    #
    def build
      sync
      output_dir.mkpath
      outputs.each(&:build)
      output_dir.touch
    end

    # Public: re-sync with the file-system.
    #
    def sync
      load_config
      validate_known_inputs
      find_new_inputs
    end

    def sync_every(period)
      @next_sync ||= 0
      now = Time.now.to_i
      if now >= @next_sync
        sync
        @next_sync = now + period
      end
    end

    # Public: check for errors.
    #
    # Returns true if any errors were encountered during the last build.
    def has_errors?
      inputs.map(&:output).compact.any?(&:error)
    end

    def last_built_at
      output_dir.mtime
    end

    def logger
      @logger ||= Logger.new(nil)
    end

    def helpers(&block)
      helper_module.module_eval(&block)
    end

    def helper_module
      @helper_module ||= Module.new
    end

    def config_inputs
      [input("_pith/config.rb")].compact
    end

    private

    attr_writer :logger

    def load_config
      config_file = input_dir + "_pith/config.rb"
      project = self
      if config_file.exist?
        eval(config_file.read, binding, config_file.to_s, 1)
      end
    end

    def load_input(path)
      i = Input.new(self, path)
      @input_map[path] = i
      if o = i.output
        @output_map[o.path] = o
      end
      i
    end

    def validate_known_inputs
      invalid_inputs = inputs.select { |i| !i.sync }
      invalid_inputs.each do |i|
        @input_map.delete(i.path)
        if o = i.output
          @output_map.delete(o.path)
        end
      end
    end

    def find_new_inputs
      input_dir.all_files.map do |input_file|
        next if input_file.in?(output_dir)
        path = input_file.relative_path_from(input_dir)
        input(path) || load_input(path)
      end
    end

  end

end
