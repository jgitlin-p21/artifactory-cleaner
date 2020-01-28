require 'forwardable'
require 'artifactory'

module Artifactory
  module Cleaner
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