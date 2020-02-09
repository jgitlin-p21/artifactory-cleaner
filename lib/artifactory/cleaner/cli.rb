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

      ##
      # Constructor for a new CLI interface
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
      ##
      # Show version information
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
      ##
      # List all available repos
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
      ##
      # Analyze usage and report where space is used
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

      desc "archive", "Download artifacts meeting specific criteria"
      option :dry_run, :aliases => '-n', :type => :boolean, :desc => "Do not actually download anything, only show what actions would have been taken"
      option :repos, :type => :array, :desc => "List of repos to download from; will download from all repos if omitted"
      option :from, :type => :string, :default => (Time.now - 2*365*24*3600).to_s, :desc => "Earliest date to include in search; defaults to 2 years ago"
      option :created_before, :type => :string, :desc => "Archive artifacts with a created date earlier than the provided value"
      option :modified_before, :type => :string, :desc => "Archive artifacts with a last modified date earlier than the provided value"
      option :downloaded_before, :type => :string, :desc => "Archive artifacts with a last downloaded date earlier than the provided value"
      option :last_used_before, :type => :string, :desc => "Archive artifacts which were created, last modified and last downloaded before the provided date"
      option :threads, :type => :numeric, :default => 4, :desc => "Number of threads to use for fetching artifact info"
      option :archive_to, :type => :string, :desc => "Save artifacts to the provided path before deletion"
      option :filter, :type => :string, :desc => "Specify a YAML file containing filter rules to use"
      ##
      # Download artifacts meeting specific criteria
      #
      # **WARNING:** This method will cause the `last_downloaded` property of all the matching artifacts to be updated;
      # therefore, using this method with a `last_used_before` switch may not be idempotent as it will cause the set of
      # artifacts matching the search to change
      #
      # Consider using `clean --archive` instead
      def archive
        dates = parse_date_options
        filter = load_artifact_filter
        archive_to = parse_archive_option
        if archive_to.nil?
          STDERR.puts "Missing required `--archive-to` option specifying a a valid, existing directory under which to store archived artifacts"
          exit Sysexits::EX_USAGE
        end

        report = {
            archived: {
                artifact_count: 0,
                bytes: 0
            },
            skipped: {
                artifact_count: 0,
                bytes: 0
            }
        }

        @controller.with_discovered_artifacts(from: dates[:from], to: dates[:to], repos: options.repos, threads: options.threads) do |artifact|
          if artifact_meets_criteria(artifact, dates, filter)
            if options.dry_run?
              STDERR.puts "Would archive #{artifact} to #{archive_to}"
            else
              @controller.archive_artifact artifact, archive_to
            end

            report[:archived][:artifact_count] += 1
            report[:archived][:bytes] += artifact.size
          else
            STDERR.puts "[DEBUG] Skipped #{artifact.inspect} because it did not meet the criteria" if options.verbose?
            report[:skipped][:artifact_count] += 1
            report[:skipped][:bytes] += artifact.size
          end
        end
        report.each do |key,values|
          puts "#{key} #{values[:artifact_count]} artifacts totaling #{Util.filesize values[:bytes]}"
        end
      end

      desc "clean", "Delete artifacts meeting specific criteria"
      option :dry_run, :aliases => '-n', :type => :boolean, :desc => "Do not actually delete anything, only show what actions would have ben taken"
      option :repos, :type => :array, :desc => "List of repos to clean; will delete from all repos if omitted"
      option :from, :type => :string, :default => (Time.now - 2*365*24*3600).to_s, :desc => "Earliest date to include in search; defaults to 2 years ago"
      option :created_before, :type => :string, :desc => "Delete artifacts with a created date earlier than the provided value"
      option :modified_before, :type => :string, :desc => "Delete artifacts with a last modified date earlier than the provided value"
      option :downloaded_before, :type => :string, :desc => "Delete artifacts with a last downloaded date earlier than the provided value"
      option :last_used_before, :type => :string, :desc => "Delete artifacts which were created, last modified and last downloaded before the provided date"
      option :threads, :type => :numeric, :default => 4, :desc => "Number of threads to use for fetching artifact info"
      option :archive_to, :type => :string, :desc => "Save artifacts to the provided path before deletion"
      option :filter, :type => :string, :desc => "Specify a YAML file containing filter rules to use"
      ##
      # Delete artifacts meeting specific criteria
      #
      # Clean up an Artifactory instance by deleting old, unused artifacts which meet given criteria
      #
      # This is a CLI interface to Artifactory::Cleaner's primary function: deleting artifacts which have not been used
      # in a long time (or which meet other criteria, determined by the powerful regex-based filters)
      def clean
        dates = parse_date_options
        filter = load_artifact_filter
        archive_to = parse_archive_option

        # Ready to locate and delete artifacts
        report = {
            deleted: {
                artifact_count: 0,
                bytes: 0
            },
            archived: {
                artifact_count: 0,
                bytes: 0
            },
            skipped: {
                artifact_count: 0,
                bytes: 0
            }
        }

        STDERR.puts "[DEBUG] controller.bucketize_artifacts from #{dates[:from]} to #{dates[:to]} repos #{options.repos}" if options.verbose?
        @controller.with_discovered_artifacts(from: dates[:from], to: dates[:to], repos: options.repos, threads: options.threads) do |artifact|
          if artifact_meets_criteria(artifact, dates, filter)
            if archive_to
              if options.dry_run?
                STDERR.puts "Would archive #{artifact} to #{archive_to}"
              else
                @controller.archive_artifact artifact, archive_to
              end

              report[:archived][:artifact_count] += 1
              report[:archived][:bytes] += artifact.size
            end

            if options.dry_run?
              STDERR.puts "Would delete #{artifact}"
            else
              @controller.delete_artifact artifact
            end

            report[:deleted][:artifact_count] += 1
            report[:deleted][:bytes] += artifact.size
          else
            STDERR.puts "[DEBUG] Skipped #{artifact.inspect} because it did not meet the criteria" if options.verbose?
            report[:skipped][:artifact_count] += 1
            report[:skipped][:bytes] += artifact.size
          end
        end
        report.each do |key,values|
          puts "#{key} #{values[:artifact_count]} artifacts totaling #{Util.filesize values[:bytes]}"
        end
      end

      private

      ##
      # Loads the Artifactory configuration from a YAML file
      def load_conf_file(path)
        config = YAML.load_file path
        config.each do |key, val|
          @config[key] = val
        end
      end

      ##
      # Initialize our Artifactory::Cleaner::Controller
      def create_controller
        @controller = Artifactory::Cleaner::Controller.new(@artifactory_config)
        @controller.verbose = true if options.verbose?
      end

      ##
      # return Ruby Time objects formed from CLI switches `--to`, `--from`, `--ctreated-before` etc
      def parse_date_options
        dates = {}
        dates[:from] = Time.parse(options.from) if options.from
        dates[:created_before] = Time.parse(options.created_before) if options.created_before
        dates[:modified_before] = Time.parse(options.modified_before) if options.modified_before
        dates[:last_used_before] = Time.parse(options.last_used_before) if options.last_used_before
        dates[:to] = [dates[:created_before], dates[:modified_before], dates[:downloaded_before], dates[:last_used_before]].compact.sort.first

        if dates[:to].nil?
          STDERR.puts "At least one end date for search must be provided (--created-before, --modified-before, --downloaded-before or --last-used-before)"
          exit Sysexits::EX_USAGE
        end

        dates
      end

      ##
      # Parse and validate value for the `--archive-to` CLI switch, ensuring it points to a valid, writable directory
      def parse_archive_option
        archive_to = options.archive_to
        if archive_to
          unless File.directory? archive_to
            STDERR.puts "#{archive_to} is not a directory. `--archive-to` expects a valid, existing directory under which to store archived artifacts"
            exit Sysexits::EX_USAGE
          end
          archive_to = File.realpath(archive_to)
          unless File.directory? archive_to and File.writable? archive_to
            STDERR.puts "Unable to write to directory #{archive_to} -- check permissions"
            exit Sysexits::EX_CANTCREAT
          end
        end
        archive_to
      end

      ##
      # Load Artifactory::Cleaner::ArtifactFilter objects from a YAML file
      def load_artifact_filter
        filter = ArtifactFilter.new
        if options.filter
          unless File.exist? options.filter and File.readable? options.filter
            STDERR.puts "Unable to read specified filter file #{options.filter}"
            exit Sysexits::EX_USAGE
          end
          rules = YAML.load_file options.filter
          rules.each {|rule| filter << rule}
        end
        filter
      end

      ##
      # Check if a given artifact meets our CLI search criteria and filters
      def artifact_meets_criteria(artifact, dates, filter)
        (dates.has_key?(:created_before) ? artifact.created < dates[:created_before] : true) and
        (dates.has_key?(:modified_before) ? artifact.last_modified < dates[:modified_before] : true) and
        (dates.has_key?(:last_used_before) ? artifact.latest_date < dates[:last_used_before] : true) and
        (filter.action_for(artifact) == :include)
      end

      ##
      #
      def repo_cols(repo, include_cols)
        include_cols.map do |col|
          repo.send(col.method).to_s
        end
      end

      ##
      # Helper method for generating CLI terminal-friendly tables of output
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

      ##
      # CLI helper method for printing details of discovered repositories to a terminal
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
