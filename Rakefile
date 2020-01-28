$LOAD_PATH.unshift File.join(File.dirname(__FILE__), "lib")

require "bundler/gem_tasks"
require "rspec/core/rake_task"

require "artifactory/cleaner/artifact_bucket"
require "artifactory/cleaner/artifact_bucket_collection"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec
