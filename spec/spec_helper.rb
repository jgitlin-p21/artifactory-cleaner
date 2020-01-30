require "bundler/setup"
require "artifactory/cleaner"

module Artifactory::Cleaner::SpecHelpers
  def generate_rule
    Artifactory::Cleaner::ArtifactFilterRule.new(
        action: :include,
        priority: (rand * 200).to_i - 100,
        property: :url,
        regex: /.*/
    )
  end

  def generate_artifact
    artifact = Artifactory::Cleaner::DiscoveredArtifact.new
    artifact.uri = 'http://yum.example.com/artifacts/test.rpm'
    artifact.size = (rand * 1024 * 1024 * 1024).floor
    artifact.last_downloaded = Time.now - rand * 3600*24*365
    artifact.last_modified = artifact.last_downloaded - rand * 3600*24*30
    artifact
  end
end

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.include Artifactory::Cleaner::SpecHelpers
end
