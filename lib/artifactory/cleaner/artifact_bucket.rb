require 'forwardable'
require 'artifactory'

module Artifactory
  module Cleaner

    ##
    # A collection of Artifacts within a date range
    #
    # An Artifactory::Cleaner::ArtifactBucket represents an "age bucket" when analyzing Artifact usage; Artifacts are
    # grouped into buckets of time to aid in developing an archive strategy.
    #
    # Artifactory::Cleaner::ArtifactBucket is largely just an Array of Artifactory::Resource::Artifact instances, with
    # logic to maintain a filesize count and properties fr the age of the artifacts within.
    #
    # This class works with the Artifactory::Cleaner::ArtifactBucketCollection class, which maintains a collection of
    # Artifactory::Cleaner::ArtifactBucket instances and handles selecting the proper one for a given Artifact
    class ArtifactBucket
      extend Forwardable
      include Enumerable

      attr_reader :min
      attr_reader :max
      attr_reader :filesize

      def initialize(min,max=nil)
        @min = min
        @max = max.nil? ? Float::INFINITY : max
        @filesize = 0
        @collection = []
      end

      delegate [:[], :slice, :clear, :first, :last, :delete, :shift, :length, :empty?, :each] => :@collection

      def covers?(age)
        age >= @min && age < @max
      end

      def []=(key, artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @collection[key] = artifact
      end

      def push(artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @collection.push artifact
        @filesize += artifact.size
        return self
      end
      alias_method :<<, :push

      def unshift(artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @collection.unshift artifact
        @filesize += artifact.size
        return self
      end

      def recalculate_filesize
        @filesize = @collection.reduce(0) {|sum,asset| sum + asset.size}
      end
    end
  end
end