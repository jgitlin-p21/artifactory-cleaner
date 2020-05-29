require 'benchmark'

module Artifactory
  module Cleaner
    ##
    # Artifactory Cleaner Logic Controller
    #
    # The Artifactory::Cleaner::Controller class provides logic central to Artifactory Cleaner.
    # Artifactory::Cleaner::Controller manages the Artifactory API client, performs searches, discovers artifacts, and
    # more. It is capable of executing tasks in a multi-threaded fashion, making multiple requests to the Artifactory
    # server in parallel.
    class Controller
      ##
      # Struct to contain the processing queues used internally within the controller
      # ---
      # The controller contains two {Queues}[https://ruby-doc.org/core-2.6/Queue.html] which are used for multi-threaded
      # processing of artifacts. The :incoming queue is fed tasks to be done, which Artifactory::Cleaner::DiscoveryWorker
      # instances pop from, process, and push the results back into the :outgoing queue. The Artifactory::Cleaner::Controller
      # will then pop from the outgoing queue and send the results back to the caller
      ProcessingQueues = Struct.new(:incoming, :outgoing)

      ##
      # Initialize and configure a new Artifactory::Cleaner::Controller
      # Params:
      # +artifactory_config+:: Hash of configuration for the Artifactory client. Used as a splat for a call to Artifactory::Client.new
      def initialize(artifactory_config)
        @artifactory_client = client = Artifactory::Client.new(**artifactory_config)
        @verbose = false
        initialize_queues
        @workers = []
        @num_workers = 6
      end

      ##
      # Is verbose output enabled? If so, the controller will print debugging and status information to STDERR
      def verbose?
        @verbose
      end

      ##
      # Enable or disable verbose mode (see Controller#verbose?)
      # When verbose mode is enabled, the controller will print debugging and status information to STDERR
      def verbose=(val)
        @verbose = !!val
      end

      ##
      # Return an ordered structure of repositories from the Artifactory server.
      #
      # This method will query Artifactory and fetch information about all available repositories. The result returned
      # is a Hash with three keys, one for each repo type: `:local`, `:remote` and `:virtual`
      # Under each of these keys is a hash mapping repo keys to their Artifactory::Resource::Repository objects
      #
      # This method may raise network errors from the underlying Artifactory client
      #
      # This method is not multi-threaded
      def discover_repos
        timing = {}
        @repos = {
            local: {},
            remote: {},
            virtual: {},
        }
        i = 0
        timing[:loop] = Benchmark.measure do
          @artifactory_client.repository_all.each do |repo|
            debuglog "[DEBUG] Found #{repo.package_type} repo: #{repo.key}"
            if repo.rclass == 'remote' && repo.url
              debuglog " +-> repo #{repo.key} is a mirror of remote at #{repo.url}"
              @repos[:remote][repo.key] = repo
            elsif repo.rclass == 'virtual' && repo.repositories
              debuglog " +-> repo #{repo.key} is a virtual repo containing: #{repo.repositories.join ', '}"
              @repos[:remote][repo.key] = repo
            else
              @repos[:local][repo.key] = repo
            end
            i += 1
          end
        end
        debuglog("[DEBUG][Perfdata] Fetched #{i} repos; timing: #{timing[:loop]}")
        @repos
      end

      ##
      # Given a list of Artifacts, fetch information about them and return a list of Artifactory::Cleaner::DiscoveredArtifact instances
      #
      # This is a helper function for #artifact_usage_search
      #
      # TODO: Document format of the `artifact_list` parameter
      #
      # This method may throw network errors from the underlying Artifactory client
      #
      # This method is multi-threaded and will spawn workers in order to make multiple concurrent HTTP connections to
      # the Artifactory API. The number of threads can be tuned with the +`threads`+ parameter. Be careful not to
      # cause excessive load on the Artifactory API!
      def discover_artifacts_from_search(artifact_list, threads: 4)
        result = []
        timing = {}
        #kill_threads
        @num_workers = threads
        timing[:enqueue] = Benchmark.measure do
          artifact_list.each {|a| queue_discovery_of_artifact a}
        end

        timing[:dequeue] = Benchmark.measure do
          until @discovery_queues.incoming.empty? and @discovery_queues.outgoing.empty? and not @workers.any? &:working?
            begin
              #debuglog("[DEBUG] Pop from outgoing queue; incoming.len=#{@discovery_queues.incoming.length}, outgoing.len=#{@discovery_queues.outgoing.length}")
              item = @discovery_queues.outgoing.pop
              if item.kind_of? Artifactory::Resource::Artifact
                result << item
                #debuglog "[DEBUG] Discovered #{item} from a child thread"
              elsif item.kind_of? Artifactory::Error::ArtifactoryError
                STDERR.puts "[ERROR] Artifactory Error from artifact fetch: #{item}"
                STDERR.puts item.full_message
                STDERR.puts "Caused by #{item.cause.full_message}" if item.cause
              elsif item.kind_of? Error
                STDERR.puts "[ERROR] Error from artifact fetch: #{item}"
                STDERR.puts item.full_message
                STDERR.puts "Caused by #{item.cause.full_message}" if item.cause
              elsif !item.nil?
                STDERR.puts "[ERROR] Got #{item} back from the discovery queue, expected an Artifactory::Resource::Artifact"
              end
            rescue => processing_ex
              STDERR.puts "[ERROR] Caught an exception when processing from the outgoing discovery queue: #{processing_ex}"
              STDERR.puts processing_ex.full_message
              STDERR.puts "Caused by #{processing_ex.cause.full_message}" if processing_ex.cause
            end
          end
        end

        begin
          kill_threads
        rescue => ex
          STDERR.puts "[ERROR] Caught an exception when killing threads: #{ex}"
          STDERR.puts ex.full_message
          STDERR.puts "Caused by #{ex.cause.full_message}" if ex.cause
        end

        debuglog("[DEBUG][Perfdata] Enqueue URLs for workers to discover: #{timing[:enqueue]}")
        debuglog("[DEBUG][Perfdata] Dequeue found Artifacts from workers: #{timing[:dequeue]}")
        total_time = timing.values.reduce(0) {|s,t| s + t.real}
        debuglog("[DEBUG] #{result.length} artifacts fetched in #{total_time.round 2} seconds")
        result
      end

      ##
      # Search for an artifact by its usage
      #
      # @example Search for all repositories with the given usage statistics
      #   Artifact.usage_search(
      #     notUsedSince: 1388534400000,
      #     createdBefore: 1388534400000,
      #   )
      #
      # @example Search for all artifacts with the given usage statistics in a repo
      #   Artifact.usage_search(
      #     notUsedSince: 1388534400000,
      #     createdBefore: 1388534400000,
      #     repos: 'libs-release-local',
      #   )
      #
      # @param [Hash] options
      #   the list of options to search with
      #
      # @option options [Artifactory::Client] :client
      #   the client object to make the request with
      # @option options [Long] :notUsedSince
      #   the last downloaded cutoff date of the artifact to search for (millis since epoch)
      # @option options [Long] :createdBefore
      #   the creation cutoff date of the artifact to search for (millis since epoch)
      # @option options [String, Array<String>] :repos
      #   the list of repos to search
      #
      # @return [Array<Resource::Artifact>]
      #   a list of artifacts that match the query
      #
      def artifact_usage_search(from: nil, to: nil, repos: nil, threads: 4)
        to = Time.now if to.nil?

        params = {
          dateFields: 'created,lastModified,lastDownloaded',
          from: from.is_a?(Time) ? from.to_i * 1000 : from.to_i,
          to: to.is_a?(Time) ? to.to_i * 1000 : to.to_i
        }
        repos = repos.compact.join(",") unless repos.nil?
        params[:repos] = repos unless repos.nil?

        result = nil

        debuglog("[DEBUG] Making Artifactory request /api/search/dates for #{params.inspect}")
        timing = {}
        timing[:search] = Benchmark.measure do
          begin
            result = @artifactory_client.get("/api/search/dates", params)
          rescue Artifactory::Error::HTTPError => err
            if err.code == 404
              debuglog "  HTTP 404 Not Found fetching: /api/search/dates -- assuming no assets for this date range"
              result = []
              #Pry::rescued(err) if defined?(Pry::rescue)
            else
              STDERR.puts "HTTP Error while performing an artifact usage search: #{err}"
              STDERR.puts err.full_message
              STDERR.puts "Parameters were: #{params.inspect}"
              STDERR.puts "Caused by #{err.cause.full_message}" if err.cause
              Pry::rescued(err) if defined?(Pry::rescue)
            end
          end
        end
        debuglog("[DEBUG] Got #{result["results"].length} results from search in #{timing[:search].real} seconds") unless result.nil? or result.empty?
        timing[:fetch] = Benchmark.measure do
          if threads > 1
            unless result.nil? or result.empty?
              result = discover_artifacts_from_search(result["results"], threads: threads)
            end
          else
            unless result.nil? or result.empty?
              result = result["results"].map do |artifact|
                a = nil
                retries = 10
                while a.nil? and retries > 0
                  begin
                    retries -= 1
                    a = Artifactory::Cleaner::DiscoveredArtifact.from_url(artifact["uri"], client: @artifactory_client)
                    a.last_downloaded = Time.parse(artifact["lastDownloaded"]) unless artifact["lastDownloaded"].to_s.empty?
                  rescue Net::OpenTimeout, Artifactory::Error::ConnectionError => err
                    STDERR.puts "[WARN] Connection Failure attempting to reach Artifactory API: #{err}"
                    debuglog "  Parameters were: #{params.inspect}"
                    debuglog "  Caused by #{err.cause.full_message}" if err.cause
                    STDERR.puts "  Retrying in 10 seconds" if retries
                    sleep 10
                  rescue Artifactory::Error::HTTPError => err
                    if err.code == 404
                      STDERR.puts "[WARN] HTTP 404 Not Found fetching: #{artifact["uri"]}"
                      retries = 0
                    else
                      retries = min(retries, 1)
                      STDERR.puts "[ERROR] HTTP Error while fetching an artifact from a usage search: #{err}"
                      debuglog err.full_message
                      debuglog "  Artifact was: #{artifact.inspect}"
                      debuglog "  Parameters were: #{params.inspect}"
                      debuglog "  Caused by #{err.cause.full_message}" if err.cause
                      Pry::rescued(err) if defined?(Pry::rescue)
                      STDERR.puts "  Will retry download once" if retries
                    end
                  end
                end
                a
              end
            end
            result.compact!
          end
        end
        debuglog("[DEBUG][Perfdata] Artifactory request /api/search/dates timing: #{timing[:search]}")
        debuglog("[DEBUG][Perfdata] Fetching artifacts timing: #{timing[:fetch]}")
        total_time = timing.values.reduce(0) {|s,t| s + t.real}
        debuglog("[DEBUG] #{result.length} artifacts fetched in #{total_time.round 2} seconds")
        result
      end

      ##
      # Iterator method for an artifact search
      #
      # the `with_discovered_artifacts` method is used to iterate over artifacts from a search which potentially covers
      # a large period of time. This method will break the period up into small chunks of time defined by the
      # `increment` argument (defaulting to 30 days) and will perform multiple searches to avoid large searches which
      # may time out or overload the Artifactory server.
      #
      # Pass a block and the block will be called with every Artifactory::Cleaner::DiscoveredArtifact that is found
      #
      # This method is not mult-threaded however it calls artifact_usage_search which is multi-threaded; number of
      # threads is controlled by the `threads` argument
      #
      # This method calls artifact_usage_search which may raise network exceptions
      #
      # Params:
      # +from+:: Time instance for the start date of the search
      # +to+:: Time instance for the end date of the search; defaults to Time.now
      # +repos+:: Optional array of repository names to search within; searches all repositories if omitted
      # +increment+:: Integer number of seconds to chunk the search period into, defaults to 30 days
      # +threads+:: Number of threads to use to fetch artifacts; defayult is 4 (passed to artifact_usage_search)
      def with_discovered_artifacts(from: nil, to: nil, repos: nil, increment: 30 * 24 * 3600, threads: 4)
        chunk_end = to || Time.now
        while chunk_end > from
          chunk_start = chunk_end - increment
          chunk_start = from if chunk_start < from
          artifact_usage_search(from: chunk_start, to: chunk_end, repos: repos, threads: threads).each do |pkg|
            yield pkg
          end
          chunk_end = chunk_start
        end
      end

      def bucketize_artifacts(from: nil, to: nil, increment: 30 * 24 * 3600, repos: nil, buckets: nil, threads: 4)
        buckets = ArtifactBucketCollection.new unless buckets.is_a? ArtifactBucketCollection
        with_discovered_artifacts(from: from, to: to, repos: repos, increment: increment, threads: threads) do |artifact|
          buckets << artifact
        end
        buckets
      end

      ##
      # Given a Artifactory::Cleaner::ArtifactBucketCollection, return a String summarizing the contents
      #
      # TODO: This really should be a method on Artifactory::Cleaner::ArtifactBucketCollection
      def bucketized_artifact_report(buckets)
        total_size = 0
        total_count = 0
        lines = buckets.map do |bucket|
          total_size += bucket.filesize
          total_count += bucket.length
          "#{bucket.length} artifacts between #{bucket.min} and #{bucket.max} days, totaling #{Artifactory::Cleaner::Util::filesize bucket.filesize}"
        end
        lines << "Total: #{Artifactory::Cleaner::Util::filesize total_size} across #{total_count} artifacts"
      end

      ##
      # Return a YAML representation of a module Artifactory::Cleaner::DiscoveredArtifact
      #
      # Provide a Artifactory::Cleaner::DiscoveredArtifact and this method will return a String containing a YAML
      # representation of the properties of the DiscoveredArtifact. If the `indent` parameter is provided, then a YAML
      # fragment will be returned, indented by `indent` spaces. This allows for "streaming" a list of Artifact YAML to
      # an IOStream
      def yaml_format(artifact, indent = 0)
        properties = [:uri, :last_downloaded, :repo, :created, :last_modified, :last_updated, :download_uri, :mime_type, :size, :checksums ]
        result = YAML.dump(properties.each_with_object({}) {|prop,export| export[prop] = artifact.send(prop) })
        if indent
          i = 0
          result.each_line.reduce('') do |str,line|
            if (i += 1) > 2
              str + (' ' * indent) + line
            elsif i == 2
                str + line
            else
              str
            end
          end
        end
      end

      ##
      # Download a copy of an artifact to the local filesystem prior to deletion
      #
      # Given an Artifactory::Resource::Artifact `artifact`, download the artifact to the local filesystem directory
      # specified by the `path` param
      #
      # **Note:** Downloading an artifact will update the artifact's last_downloaded date so it may no longer match the
      # same search criteria it originally die (if last_downloaded was used to discover this artifact)
      #
      # This method is meant to be used prior to calling `delete_artifact`
      def archive_artifact(artifact, path)
        path = File.dirname(File.join(path, URI.parse(artifact.download_uri).path.split( artifact.repo )[1]))

        debuglog "[DEBUG] downloading #{artifact} (#{artifact.uri}) to #{path}"
        archived_file = nil
        timing = Benchmark.measure do
          archived_file = artifact.download(path)
        end

        debuglog "[DEBUG] #{artifact.uri} #{Util.filesize artifact.size} downloaded in #{timing.real.round(2)} seconds (#{Util.filesize(artifact.size/timing.real)})/s"

        raise ArchiveFileNotWritten, "Failed to write to #{archived_file}" unless File.exist? archived_file
        raise ArchiveFileNotWritten, "Archive file is empty: #{archived_file}" unless File.size? archived_file
        raise ArchiveFileSizeMismatch, "#{path} size mismatch (#{File.size(archived_file)} != #{artifact.size})" unless File.size(archived_file) == artifact.size
      end

      ##
      # Delete an artifact from the Artifactory server
      #
      # Given an Artifactory::Resource::Artifact `artifact`, delete it from the Artifactory server. **This is a
      # destructive operation -- use with caution!**
      #
      # Consider using `archive_artifact` first to save artifacts locally
      #
      # This function writes to the remote Artifactory server (specifically it makes a delete call)
      def delete_artifact(artifact)
        debuglog "[DEBUG] DELETE Artifact #{artifact} at #{artifact.uri}!"
        artifact.delete
      end

      ##
      # Deprecated, do not use
      def catagorize_old_assets(days)
        buckets = {
            730 => {count: 0, size: 0},
            365 => {count: 0, size: 0},
            180 => {count: 0, size: 0},
            90  => {count: 0, size: 0},
            30  => {count: 0, size: 0},
        }
        discover_repos
        @repos[:local].each_pair do |id,repo|
          begin
            pkgs = 0
            purgable = 0
            timings = Benchmark.bm(12) do |bm|
              debuglog "Searching Repo #{id}:"
              old_packages = nil
              bm.report('api call') {
                old_packages = @artifactory_client.artifact_usage_search(
                    notUsedSince: (Time.now.to_i - 24 * 3600 * days) * 1000,
                    createdBefore: (Time.now.to_i - 24 * 3600 * days) * 1000,
                    repos: id
                )
              }
              debuglog "  Artifactory search returned #{old_packages.length} assets older than #{days}..."
              bm.report('loop') { old_packages.each_with_index do |pkg,i|
                pkgs += 1
                uri = URI(pkg.uri)
                purgable += pkg.size
                # Calculate the age of this package in days and increment the bucket it belongs in
                age = (Time.now - pkg.last_modified)/(3600*24)
                if (bucket = buckets.keys.find {|v| age >= v })
                  buckets[bucket][:count] += 1
                  buckets[bucket][:size] += pkg.size
                end
                debuglog "  ##{i}: #{File.basename(uri.path)} #{Util.filesize pkg.size} Created #{pkg.created} Modified #{pkg.last_modified}"
              end }
            end
            debuglog "Found #{pkgs} assets from #{id} older than #{days} days totaling #{Util.filesize purgable} in #{timings.reduce {|sum, t| sum + t.real}} seconds"
          rescue => ex
            STDERR.puts "Caught an exception trying to handle repo #{id}: #{ex}"
            STDERR.puts ex.full_message
            STDERR.puts "Caused by #{ex.cause.full_message}" if ex.cause
          end
        end

        buckets.each_pair do |age,bucket|
          debuglog "#{bucket[:count]} packages older than #{age} days, totaling #{Util.filesize bucket[:size]}"
        end
        
        buckets
      end

      ##################################################################################################################

      private

      ##
      # debug/verbose logging
      def debuglog(msg)
        STDERR.puts msg if @verbose
      end

      ##
      # Initialize empty artifact discovery queues
      def initialize_queues
        @discovery_queues = ProcessingQueues.new
        @discovery_queues.incoming = Queue.new
        @discovery_queues.outgoing = Queue.new
      end

      ##
      # make sure we have the desired number of worker threads
      def spawn_threads
        while @workers.length < @num_workers
          @workers << DiscoveryWorker.new(@discovery_queues, @artifactory_client).start
          debuglog "[DEBUG] Spawned #{@workers.last} to process discovery calls"
        end
      end

      ##
      # given artifact data, add it to the queue for processing and make sure we have workers to process it
      def queue_discovery_of_artifact(artifact_data)
        @discovery_queues.incoming.push(artifact_data)
        debuglog "[DEBUG] Queued #{artifact_data['uri']} for discovery"
        spawn_threads
      end

      ##
      # Forcibly terminate all threads
      # TODO: add a graceful terminate method
      def kill_threads
        @workers.each &:kill
        @workers = []
      end
    end
  end
end