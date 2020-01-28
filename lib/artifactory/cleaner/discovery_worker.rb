module Artifactory
  module Cleaner
    class DiscoveryWorker
      def initialize(processing_queues, artifactory_client)
        @running = false
        @working = false
        @thread = nil
        @queues = processing_queues
        @artifactory_client = artifactory_client
      end

      def running?
        @running
      end

      def working?
        @working
      end

      def alive?
        @thread ? @thread.alive? : false
      end

      def start
        @running = true
        @thread = Thread.new do
          while running?
            process @queues.incoming.pop(false)
          end
        end
        self
      end

      def shutdown(timeout = 300)
        @running = false
        @thread.join(timeout) if @thread and @thread.alive?
      end

      def stop
        @running = false
        @thread.kill if @thread and @thread.alive?
        @thread = nil
      end
      alias_method :kill, :stop

      def to_s
        "#<#{self.class}:#{self.object_id}; #{running? ? 'running' : 'not running'}, #{working? ? 'working' : 'idle'}, #{alive? ? 'alive' : 'dead'}>"
      end

      private

      def log(msg)
        STDERR.puts msg
      end

      def process(payload)
        @working = true
        begin
          @queues.outgoing.push discover_artifact_from payload
        rescue => ex
          return ex
        ensure
          @working = false
        end
      end

      def discover_artifact_from(artifact_info, retries = 10)
        artifact = nil
        while retries > 0
          begin
            retries -= 1
            artifact = Artifactory::Cleaner::DiscoveredArtifact.from_url(artifact_info["uri"], client: @artifactory_client)
            artifact.last_downloaded = Time.parse(artifact_info["lastDownloaded"]) unless artifact_info["lastDownloaded"].to_s.empty?
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
              log "[WARN] HTTP 404 Not Found fetching: #{artifact["uri"]}"
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