require 'artifactory'

module Artifactory
  module Cleaner
    class DiscoveredArtifact < Artifactory::Resource::Artifact
      attribute :last_downloaded

      def earliest_date
        self.earliest_date_from(self)
      end

      def latest_date
        self.latest_date_from(self)
      end

      def self.earliest_date_from(artifact)
        [
            artifact.created,
            artifact.last_modified,
            artifact.respond_to?(:last_downloaded) ? artifact.last_downloaded : nil,
        ].compact.last
      end

      def self.latest_date_from(artifact)
        [
            artifact.created,
            artifact.last_modified,
            artifact.respond_to?(:last_downloaded) ? artifact.last_downloaded : nil,
        ].compact.sort.last
      end
    end
  end
end
