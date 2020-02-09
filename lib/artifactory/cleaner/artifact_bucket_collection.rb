require 'forwardable'
require 'artifactory'

module Artifactory
  module Cleaner

    ##
    # Organize Artifacts by age bucket for analysis
    #
    # An Artifactory::Cleaner::ArtifactBucketCollection represents "age buckets" used for analyzing Artifact usage.
    # Artifacts are grouped into buckets of time to aid in developing an archive strategy. This class maintains a
    # list of buckets and handles the logic for sorting Artifacts into those buckets.
    #
    # Artifactory::Cleaner::ArtifactBucketCollection is largely just an Array of Artifactory::Cleaner::ArtifactBucket
    # instances, with logic to sort and select them and logic to distribute Artifactory::Resource::Artifact instances
    # into the proper Artifactory::Cleaner::ArtifactBucket
    class ArtifactBucketCollection
      extend Forwardable
      include Enumerable

      def initialize(buckets = [30,60,90,180,365,730,1095,nil])
        @buckets = []
        define_buckets(buckets)
      end

      delegate [:length, :each, :first, :last, :each] => :@buckets

      ##
      # Remove all Artifacts from this collection
      #
      # Calls `clear` on every bucket within this collection
      def clear
        @buckets.each &:clear
      end

      ##
      # Adjust the bucket sizes within this collection
      #
      # Given an Enumerable of ages (as integer values of days) define buckets representing those periods within this
      # collection. This method is similar to the constructor: provide an Enumerable where each value represents a
      # bucket size and new buckets will be added to this collection representing the ages (in days) contained within
      # `bucket_list`
      #
      # TODO: This will not update older buckets or move artifacts around, so if buckets were already defined then this
      # method may result in an invalid configuration, E.G. overlapping buckets or artifacts which are no longer in
      # the desired buckets. For best results, call this method on an ArtifactBucketCollection for which you already
      # know the bucket sizes and to which no artifacts have yet been added
      def define_buckets(bucket_list)
        last_size = 0
        bucket_list.each do |size|
          @buckets << Artifactory::Cleaner::ArtifactBucket.new(last_size,size)
          last_size = size
        end
      end

      ##
      # Return an Array containing the bucket sizes of this collection.
      #
      # Returns the `max` property from every bucket within this collection, thus representing the bucket sizes this
      # collection contains (as a properly configured ArtifactBucketCollection has the min of each bucket set to the max
      # of the previous bucket, thus covering an entire time range)
      def bucket_sizes
        @buckets.map &:max
      end

      ##
      # Total number of Artifacts within this collection
      #
      # Returns the sum of the length of all buckets within this collection
      def artifact_count
        @buckets.reduce(0) { |sum, bkt| sum + bkt.length }
      end

      ##
      # Add a new artifact to this collection
      #
      # Given an Artifactory::Resource::Artifact `artifact`, find the proper ArtifactBucket within this ArtifactBucketCollection
      # and add the artifact ton that bucket
      #
      # Aliased as `<<`
      def add(artifact)
        age = (Time.now - Artifactory::Cleaner::DiscoveredArtifact.latest_date_from(artifact))/(3600*24)

        if (bucket = @buckets.find {|b| b.covers? age})
          bucket << artifact
        else
          raise RangeError, "No bucket available for an artifact of age #{age.floor} days"
        end
        self
      end
      alias_method :<<, :add

      ##
      # Accessor for a bucket of a given age
      #
      # Returns the bucket which covers the period `age` (represented as an artifact age, in days)
      #
      # Aliased as `[]`
      def bucket(age)
        @buckets.find {|b| b.covers? age}
      end
      alias_method :[], :bucket

      ##
      # Human-readable summary of this collection
      #
      # Returns a string summarizing each bucket within this collection: how many packages and what filesize each bucket
      # contains. Used when analyzing artifact searches: artifacts discovered from a search are placed into an
      # ArtifactBucketCollection and then this report can be produced to describe how old the artifacts are and where
      # opportunities for cleaning exist.
      def report
        buckets.map {|bucket|
          "#{bucket.length} packages between #{bucket.min} and #{bucket.max} days, totaling #{Artifactory::Cleaner::Util::filesize bucket.filesize}"
        }.join("\n")
      end
    end
  end
end