module Artifactory
  module Cleaner
    ##
    # Filter a collection of artifacts based on include/deny rules
    #
    # The Artifactory::Cleaner::ArtifactFilterRile class represents a whitelist or blacklist entry. It matches a package
    # and then targets that package for inclusion or exclusion.
    class ArtifactFilterRule
      include Comparable

      def initialize(action: :include, priority: 0, property: :uri, regex: //)
        @regex = regex if regex.is_a? Regexp
        @action = action
        @priority = priority.to_i
        @property = property.to_sym
      end

      attr_reader :regex

      ##
      # Change the regex of this rule
      def regex=(re)
        raise TypeError, 'Expected a Regexp' unless re.is_a? Regexp
        @regex = re
      end
      alias_method :regexp, :regex
      alias_method :regexp=, :regex=

      # TODO: Allow changing priority. Right now this would cause problems because if the rule is in a filtr, the filter won't be sorted properly after this change.
      attr_reader :priority
      attr_accessor :property
      attr_accessor :action

      ##
      # Does this rule trigger an action on a given artifact?
      #
      # This method returns true if the given artifact matches the criteria of this rule, and the rule is of type :include
      def action_for(artifact)
        if matches?(artifact)
          @action
        else
          false
        end
      end

      ##
      # Does this rule determine that an artifact should be included?
      #
      # This method returns true if the given artifact matches the criteria of this rule, and the rule is of type :include
      def includes?(artifact)
        @type == :include && matches?(artifact)
      end

      ##
      # Does this rule determine that an artifact should be excluded?
      #
      # This method returns true if the given artifact matches the criteria of this rule, and the rule is of type :exclude
      def excludes?(artifact)
        @type == :exclude && matches?(artifact)
      end

      ##
      # Does this rule match a given package?
      #
      # Returns true if the `property` of a given artifact matches the `regex`
      def matches?(artifact)
        @regex.is_a? Regexp and @regex.match?(artifact.send(@property).to_s)
      end

      ##
      # Compare priority with another rule
      def <=>(other_rule)
        if other_rule.is_a? ArtifactFilterRule
          @priority <=> other_rule.priority
        else
          nil
        end
      end
    end
  end
end