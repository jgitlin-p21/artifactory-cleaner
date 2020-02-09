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

      ##
      # ArtifactBucket constructor
      #
      # Params:
      # +min+:: Lower bound (in days) for the age of artifacts this bucket should contain
      # +max+:: Upper bound (in days) for the age of artifacts this bucket should contain, defaults to none (infinity)
      def initialize(min,max=nil)
        @min = min
        @max = max.nil? ? Float::INFINITY : max
        @filesize = 0
        @collection = []
      end

      delegate [:[], :slice, :clear, :first, :last, :delete, :shift, :length, :empty?, :each] => :@collection

      ##
      # Given an age (in days) return true if this bucket covers that age (if it's within the min and max of this bucket)
      def covers?(age)
        age >= @min && age < @max
      end

      ##
      # Update an artifact in the bucket
      #
      # TODO: This method does not validate if the artifact still belongs in this bucket by age
      def []=(key, artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @filesize -= @collection[key].size if @collection[key].is_a? Artifactory::Resource::Artifact
        @filesize += artifact.size
        @collection[key] = artifact
      end

      ##
      # Add an artifact to the end of this bucket
      #
      # Calls push on the Array which backs this bucket
      #
      # Aliased as method `<<`
      #
      # TODO: This method does not validate if the artifact belongs in this bucket by age
      #
      # @see: Array#push
      def push(artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @collection.push artifact
        @filesize += artifact.size
        self
      end
      alias_method :<<, :push

      ##
      # Add an artifact to the beginning of this bucket
      #
      # Calls unshift on the Array which backs this bucket
      #
      # TODO: This method does not validate if the artifact belongs in this bucket by age
      #
      # @see Array#unshift
      def unshift(artifact)
        raise TypeError, "expected Artifactory::Resource::Artifact, got #{artifact.class.name}" unless artifact.is_a? Artifactory::Resource::Artifact
        @collection.unshift artifact
        @filesize += artifact.size
        self
      end

      ##
      # Recalculate the file size of this bucket by adding up the size of all artifacts it contains
      #
      # This method forces recalculation of the total fize size of all artifacts within this bucket; the filesize is
      # tracked automatically as artifacts are added, so thi method should be unnecessary. It is av available in case
      # the tracking built in to `push`/`unshift`/`[]=` hsa a bug, or in case artifact sizes somehow change
      def recalculate_filesize
        @filesize = @collection.reduce(0) {|sum,asset| sum + asset.size}
      end
    end
  end
end