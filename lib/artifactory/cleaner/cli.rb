require 'thor'
require 'yaml'
require 'sysexits'
require 'time'

module Artifactory
  module Cleaner

    ##
    # Command Line Interface class, powers the artifactory-cleaner terminal command
    # ---
    # A single Artifactory::Cleaner::CLI instance is created by the bin/artifactory_cleaner command for parsing options and
    # executing the command specified by the user. The Artifactory::Cleaner::CLI uses {Thor}[https://github.com/erikhuda/thor]
    # to provide git command/subcommand style ARGV parsing
    #
    # @see exe/artifactory-cleaner
    #
    # @see https://github.com/erikhuda/thor
    class CLI < Thor
      class_option :verbose, :aliases => %w(-v), :type => :boolean, :desc => "Verbose mode; print additional information to STDERR"
      class_option :conf_file, :aliases => %w(-c), :type => :string, :desc => "Provide a path to configuration file with endpoint and API key"
      class_option :endpoint, :aliases => %w(-e), :type => :string, :desc => "Artifatcory endpoint URL"
      class_option :api_key, :aliases => %w(-k), :type => :string, :desc => "Artifactory API key"

      RepoTableCol = Struct.new(:method, :heading, :only)
      def self.repo_table_cols
        [
          RepoTableCol.new(:key, 'ID', nil),
          RepoTableCol.new(:package_type, 'Type', nil),
          RepoTableCol.new(:rclass, 'Class', :local),
          RepoTableCol.new(:url, 'URL', :remote),
          RepoTableCol.new(:description, 'Description', nil),
          RepoTableCol.new(:notes, 'Notes', nil),
          RepoTableCol.new(:blacked_out?, 'Blacked Out', nil),
          RepoTableCol.new(:yum_root_depth, 'YUM Root Depth', nil),
          RepoTableCol.new(:checksum_policy_type, 'Checksum Policy', nil),
          RepoTableCol.new(:includes_pattern, 'Includes Pattern', nil),
          RepoTableCol.new(:excludes_pattern, 'Excludes Pattern', nil),
          RepoTableCol.new(:handle_releases, 'Releases', nil),
          RepoTableCol.new(:handle_snapshots, 'Snapshots', nil),
          RepoTableCol.new(:property_sets, 'Property Sets', nil),
          RepoTableCol.new(:repo_layout_ref, 'Layout', nil),
          RepoTableCol.new(:repositories, 'Included Repos', nil),
          RepoTableCol.new(:inspect, 'Inspection'),
        ]
      end

      def self.default_repo_table_cols
        [:key, :package_type, :rclass, :url, :description]
      end

      def initialize(*args)
        super
        @config = {}
        begin
          load_conf_file options.conf_file if options.conf_file
        rescue => ex
          STDERR.puts "Unable to load config from #{options.conf_file}: #{ex}"
          exit Sysexits::EX_DATAERR
        end
        @artifactory_config = {
           endpoint: options[:endpoint] || @config['endpoint'],
           api_key: options[:api_key] || @config['api-key'],
        }
        @repo_table_cols = Artifactory::Cleaner::CLI.repo_table_cols
        #invoke :create_controller
        create_controller
      end

      desc "version", "Show version information"
      def version
        STDERR.puts "Artifactory::Cleaner version #{Artifactory::Cleaner::VERSION}"
        STDERR.puts "Copyright (C) 2020 Pinnacle 21, inc. All Rights Reserved"
      end

      desc "list-repos", "List all available repos"
      option :details, :type => :boolean
      option :no_headers, :aliases => %w(-H), :type => :boolean, :desc => "Used for scripting mode.  Do not print headers and separate fields by a single tab instead of arbitrary white space."
      option :output, :aliases => %w(-o), :type => :string, :desc => " A comma-separated list of properties to display. Available properties are: #{(Artifactory::Cleaner::CLI.repo_table_cols.map &:method ).join(',')}"
      option :local, :type => :boolean, :default => true, :desc => "Include local repositories"
      option :remote, :type => :boolean, :default => false, :desc => "Include remote (replication) repositories"
      option :virtual, :type => :boolean, :default => false, :desc => "Include virtual (union) repositories"
      def list_repos()
        repo_info_table = []
        repos = @controller.discover_repos
        repo_kinds = []
        repo_kinds << :local if options.local?
        repo_kinds << :remote if options.remote?
        repo_kinds << :virtual if options.virtual?
        include_cols = get_repo_cols(repo_kinds)
        repos[:local].each {|k, r| repo_info_table << repo_cols(r, include_cols)} if options.local?
        repos[:remote].each {|k, r| repo_info_table << repo_cols(r, include_cols)} if options.remote?
        repos[:virtual].each {|k, r| repo_info_table << repo_cols(r, include_cols)} if options.virtual?
        print_repo_list repo_info_table, include_cols
      end

      desc "usage-report", "Analyze usage and report where space is used"
      option :details, :type => :boolean, :desc => "Produce a detailed report listing all artifacts"
      option :buckets, :type => :string, :desc => "Comma separated list of bucket sizes (age in days) to group artifacts by"
      option :repos, :type => :array, :desc => "List of repos to analyze; will analyze all repos if omitted"
      option :from, :type => :string, :default => (Time.now - 2*365*24*3600).to_s
      option :to, :type => :string, :default => (Time.now).to_s
      option :threads, :type => :numeric, :default => 4
      def usage_report
        begin
          from = Time.parse(options.from)
          to = Time.parse(options.to)
        rescue => ex
          STDERR.puts "Unable to parse time format. Please use: YYYY-MM-DD HH:II:SS"
          STDERR.puts ex
          exit Sysexits::EX_USAGE
        end

        begin
          STDERR.puts "[DEBUG] controller.bucketize_artifacts from #{from} to #{to} repos #{options.repos}" if options.verbose?
          buckets = @controller.bucketize_artifacts(
              from: from,
              to: to,
              repos: options.repos,
              threads: options.threads,
          )

          @controller.bucketized_artifact_report(buckets).each { |l| STDERR.puts l }
          if options.details?
            puts "# Detailed Bucket Report:"
            puts "buckets:"
            buckets.each do |bucket|
              puts "#--  #{bucket.length} artifacts between #{bucket.min} and #{bucket.max} days old repo_info_table #{bucket.filesize} bytes --"
              puts "  - min: #{bucket.min} # days old"
              puts "    max: #{bucket.max} # days old"
              if bucket.empty?
                puts "    artifacts: []"
              else
                puts "    artifacts:"
                bucket.each { |pkg| puts "    - #{@controller.yaml_format(pkg,6)}" }
              end
            end
          end
        rescue => err
          STDERR.puts "An exception occured while generating the usage report: #{err}"
          STDERR.puts err.full_message
          STDERR.puts "Caused by: #{err.cause.full_message}" if err.cause
          Pry::rescued(err) if defined?(Pry::rescue)
          exit Sysexits::EX_UNAVAILABLE
        end
      end

      private

      def load_conf_file(path)
        config = YAML.load_file path
        config.each do |key, val|
          @config[key] = val
        end
      end

      def create_controller
        @controller = Artifactory::Cleaner::Controller.new(@artifactory_config)
        @controller.verbose = true if options.verbose?
      end

      def repo_cols(repo, include_cols)
        include_cols.map do |col|
          repo.send(col.method).to_s
        end
      end

      def get_repo_cols(repo_kinds)
        if options.details?
          selected_cols =
              if options.output.nil?
                Artifactory::Cleaner::CLI.default_repo_table_cols
              else
                options.output.split(',').map &:to_sym
              end
          @repo_table_cols.select do |col|
            (col.only.nil? or repo_kinds.include? col.only) and (selected_cols.include? col.method)
          end
        else
          @repo_table_cols.select {|col| col.method == :key}
        end
      end

      def print_repo_list(repo_info_table, include_cols)
        if options.no_headers || !options.details
          repo_info_table.each {|row| puts row.join("\t")}
        else
          headers = include_cols.map &:heading
          widths = headers.map {|h| h.length + 1}
          repo_info_table.each do |row|
            row.each_with_index { |val, index| widths[index] = [widths[index], val.length + 1].max  }
          end
          total_width = widths.reduce(0) {|s,v| s+v}
          headers.each_with_index { |h, i| print h.ljust(widths[i], ' ') }
          puts ""
          puts '-'.ljust(total_width, '-')
          repo_info_table.each do |row|
            row.each_with_index { |v, i| print v.ljust(widths[i], ' ')  }
            puts ""
          end
        end
      end
    end
  end
end
