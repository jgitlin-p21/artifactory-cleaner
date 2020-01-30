module Artifactory
  module Cleaner
    ##
    # Filter a list of artifacts based on a series of include/exclude rules
    #
    # Artifactory::Cleaner::ArtifactFilter is used to filter a list of artifacts based on rules. It is both a whitelist
    # and a blacklist: it maintains a list of rules in sorted priority order, and the first rule which matches a given
    # artifact determines the action for that artifact (include or exclude)
    #
    # Rules are stored in ascending priority order with lower numbers being greater priority. (Think "Priority 1" or
    # process queue scheduling via `nice` value under Linux.
    class ArtifactFilter
      extend Forwardable
      include Enumerable

      ##
      # ArtifactFilter constructor
      def initialize()
        @rules = []
        @sorted = false
        @default_action = :include
      end

      attr_accessor :default_action

      delegate [:length, :clear, :empty?] => :@rules

      ##
      # Access a rule by index
      def [](*args)
        sort_if_needed
        @rules[*args]
      end

      ##
      # Update a given rule
      def []=(key, rule)
        raise TypeError, "expected Artifactory::Cleaner::ArtifactFilterRule, got #{rule.class.name}" unless rule.is_a? Artifactory::Cleaner::ArtifactFilterRule
        @rules[key] = rule
        @sorted = false
      end

      ##
      # Slice the filter rules, see Array#slice
      def slice(*args, &block)
        sort_if_needed
        @rules.slice(*args, &block)
      end

      ##
      # Search for a rule
      def bsearch(*args, &block)
        sort_if_needed
        @rules.bsearch(*args, &block)
      end

      ##
      # Get the first (numerically first priority) rule
      def first
        sort_if_needed
        @rules.first
      end

      ##
      # Get the last (numerically last priority) rule
      def last
        sort_if_needed
        @rules.last
      end

      ##
      # Iterate over all rules (See Enumerable#each)
      def each(&block)
        sort_if_needed
        @rules.each(&block)
      end

      ##
      # Add rules to this filter
      #
      # Like Array#push this method adds a rule to the end of the array, however the array will be sorted in priority
      # order before usage so addition at the end or the beginning is somewhat meaningless
      def push(rule)
        raise TypeError, "expected Artifactory::Cleaner::ArtifactFilterRule, got #{rule.class.name}" unless rule.is_a? Artifactory::Cleaner::ArtifactFilterRule
        @rules.push rule
        @sorted = false
        self
      end
      alias_method :<<, :push

      ##
      # Add a rule to this filter
      #
      # Like Array#unshift this method adds a rule to the beginning of the array, however the array will be sorted in
      # priority order before usage so addition at the end or the beginning is somewhat meaningless
      def unshift(rule)
        raise TypeError, "expected Artifactory::Cleaner::ArtifactFilterRule, got #{rule.class.name}" unless rule.is_a? Artifactory::Cleaner::ArtifactFilterRule
        @rules.unshift rule
        @sorted = false
        self
      end

      ##
      # Ensure the filterset is sorted properly. Should not need to be called manually
      def sort!
        sort_if_needed
        self
      end

      ##
      # Filter a given Artifactory::Resource::Artifact and return the action which should be taken
      #
      # Returns a symbol from the rule which matches this artifact, or the default action (:include) if no rules matched
      def action_for(artifact)
        sort_if_needed
        @rules.each do |rule|
          action = rule.action_for artifact
          return action if action
        end
        @default_action
      end


      ##
      # Filter a collection of Artifactory::Resource::Artifact instances, returning the ones for which the action matches
      #
      # Takes an Enumerable filled with Artifactory::Resource::Artifact instances and returns a filtered enumerable for
      # which all artifacts matched the desired action after applying the filter rules to each item. `action` defaults
      # to :include but can be changed if desired
      #
      # Unlike Array#filter +this method does not take a block+
      def filter(artifacts, action = :include)
        artifacts.filter {|artifact| action_for(artifact) == action}
      end

      private

      ##
      # Sort the array but avoid needless sorting
      def sort_if_needed
        @rules.sort! unless @sorted
        @sorted = true
      end
    end
  end
end