require 'uri'
require 'artifactory'

module Artifactory
  module Cleaner
    ##
    # An Artifact discovered during a repository search
    #
    # This class is a wrapper of Artifactory::Resource::Artifact because the parent class does not have a concept of
    # `last_downloaded` nor the most recent date for any action on an Artifact. These are important to deciding if an
    # Artifcat should be deleted
    class DiscoveredArtifact < Artifactory::Resource::Artifact
      ##
      # Time representing the date and time this artifact was last downloaded by a client (presumably to be installed)
      attribute :last_downloaded

      ##
      # What's the earliest Time of any of the date/time properties on this object?
      def earliest_date
        self.class.earliest_date_from(self)
      end

      ##
      # What's the most recent Time of any of the date/time properties on this object?
      def latest_date
        self.class.latest_date_from(self)
      end

      ##
      # The filename componet (basename) of this artifact's URL
      def filename
        uri = URI(self.uri)
        File.basename(uri.path)
      end

      ##
      # A string representation of this artifact
      def to_s
        "#<DiscoveredArtifact #{filename} last accessed #{latest_date}>"
      end

      ##
      # Given an Artifactory::Resource::Artifact, return the value of the earliest date property on that object
      #
      # Designed to answer the question "what's the first time anything happened to a given Artifact?", this method
      # returns the earliest (longest ago) date from the given artifact's created, last modified and last downloaded
      # timestamps.
      def self.earliest_date_from(artifact)
        [
            artifact.created,
            artifact.last_modified,
            artifact.respond_to?(:last_downloaded) ? artifact.last_downloaded : nil,
        ].compact.sort.first
      end

      ##
      # Given an Artifactory::Resource::Artifact, return the value of the latest date property on that object
      #
      # Designed to answer the question "what's the most recent interaction with a given Artifact?", this method
      # returns the latest (most recent) date from the given artifact's created, last modified and last downloaded
      # timestamps.
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
