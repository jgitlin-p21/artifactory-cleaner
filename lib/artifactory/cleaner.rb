require "artifactory/cleaner/version"
require "artifactory/cleaner/util"
require "artifactory/cleaner/discovered_artifact"
require "artifactory/cleaner/artifact_bucket"
require "artifactory/cleaner/artifact_bucket_collection"
require "artifactory/cleaner/artifact_filter"
require "artifactory/cleaner/artifact_filter_rule"
require "artifactory/cleaner/discovery_worker"
require "artifactory/cleaner/controller"
require "artifactory/cleaner/cli"

module Artifactory
  module Cleaner
    class Error < StandardError; end

    class ArchiveError < RuntimeError; end
    class ArchiveFileNotWritten < ArchiveError; end
    class ArchiveFileSizeMismatch < ArchiveError; end

  end
end
