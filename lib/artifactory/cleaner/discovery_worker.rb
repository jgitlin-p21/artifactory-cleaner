module Artifactory
  module Cleaner
    ##
    # Helper class representing Threads spawned to discover Artifacts
    class DiscoveryWorker
      def initialize(processing_queues, artifactory_client)
        @running = false
        @working = false
        @thread = nil
        @queues = processing_queues
        @artifactory_client = artifactory_client
      end

      ##
      # Is this DiscoveryWorker running, listening to the queue and processing requests
      def running?
        @running
      end

      ##
      # Is this DiscoveryWorker currently processing a request?
      #
      # when #running? is true and #working? is not, then the worker is idle, blocked, waiting for an action.
      #
      # when #working? is true, there will be at least one more result pushed to the outgoing queue when the current
      # request finishes
      def working?
        @working
      end

      ##
      # Is the Thread for this worker alive?
      def alive?
        @thread ? @thread.alive? : false
      end

      ##
      # Start the DiscoveryWorker and begin processing from the queue
      def start
        @running = true
        @thread = Thread.new do
          while running?
            process @queues.incoming.pop(false)
          end
        end
        self
      end

      ##
      # Stop the Thread and re-join the parent
      def shutdown(timeout = 300)
        @running = false
        @thread.join(timeout) if @thread and @thread.alive?
      end

      ##
      # Forcibly kill the Thread and destroy it
      def stop
        @running = false
        @thread.kill if @thread and @thread.alive?
        @thread = nil
      end
      alias_method :kill, :stop

      ##
      # String representation of this DiscoveryWorker and it's status
      def to_s
        "#<#{self.class}:#{self.object_id}; #{running? ? 'running' : 'not running'}, #{working? ? 'working' : 'idle'}, #{alive? ? 'alive' : 'dead'}>"
      end

      private

      ##
      # debug / verbose logging
      # TODO: add a verbose conditional, maybe a different log destination
      def log(msg)
        STDERR.puts msg
      end

      ##
      # pop from the incoming queue, process, push result to outgoing
      def process(payload)
        @working = true
        begin
          @queues.outgoing.push(discover_artifact_from(payload))
        rescue => ex
          STDERR.puts "[Error] Exception in thread: #{ex.full_message}"
          @queues.outgoing.push(ex)
        ensure
          @working = false
        end
      end

      ##
      # main method, given artifact info, generate a Artifactory::Cleaner::DiscoveredArtifact
      #
      # this method makes HTTP calls to the Artifactory API
      def discover_artifact_from(artifact_info, retries = 10)
        artifact = nil
        while retries > 0
          begin
            #STDERR.puts "[DEBUG] thread discover_artifact_from #{artifact_info["uri"]} start"
            retries -= 1
            artifact = Artifactory::Cleaner::DiscoveredArtifact.from_url(artifact_info["uri"], client: @artifactory_client)
            artifact.last_downloaded = Time.parse(artifact_info["lastDownloaded"]) unless artifact_info["lastDownloaded"].to_s.empty?
            #STDERR.puts "[DEBUG] thread discover_artifact_from #{artifact_info["uri"]} end"
            return artifact
          rescue Net::OpenTimeout, Artifactory::Error::ConnectionError => err
            artifact = err
            if retries
              log "[WARN] Connection Failure attempting to reach Artifactory API: #{err}; Retrying in 10 seconds"
              sleep 10
            end
          rescue Artifactory::Error::HTTPError => err
            artifact = err
            if err.code == 404
              log "[WARN] HTTP 404 Not Found fetching: #{artifact_info["uri"]}"
              return nil
            else
              retries = min(retries, 1)
              log "[ERROR] HTTP Error while fetching an artifact from a usage search: #{err}; #{retries ? 'Will' : 'Will not'} retry"
            end
          end
        end
        artifact
      end
    end
  end
end