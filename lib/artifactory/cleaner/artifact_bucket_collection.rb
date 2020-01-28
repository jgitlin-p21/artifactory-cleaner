require 'forwardable'
require 'artifactory'

module Artifactory
  module Cleaner
    class ArtifactBucketCollection
      extend Forwardable
      include Enumerable

      def initialize(buckets = [30,60,90,180,365,730,1095,nil])
        @buckets = []
        define_buckets(buckets)
      end

      delegate [:length, :each, :first, :last, :each] => :@buckets

      def clear
        @buckets.each &:clear
      end

      def define_buckets(bucket_list)
        last_size = 0
        bucket_list.each do |size|
          @buckets << Artifactory::Cleaner::ArtifactBucket.new(last_size,size)
          last_size = size
          # TODO: This will not update older buckets or move artifacts around
        end
      end

      def bucket_sizes
        @buckets.map &:max
      end

      def artifact_count
        @buckets.reduce(0) { |sum, bkt| sum + bkt.length }
      end

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

      def bucket(age)
        @buckets.find {|b| b.covers? age}
      end
      alias_method :[], :bucket

      def report
        buckets.map {|bucket|
          "#{bucket.length} packages between #{bucket.min} and #{bucket.max} days, totaling #{Artifactory::Cleaner::Util::filesize bucket.filesize}"
        }.join("\n")
      end
    end
  end
end