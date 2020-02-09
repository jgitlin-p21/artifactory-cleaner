# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative 'lib/artifactory/cleaner/version'

Gem::Specification.new do |spec|
  spec.name          = "artifactory-cleaner"
  spec.version       = Artifactory::Cleaner::VERSION
  spec.authors       = ["Josh Gitlin"]
  spec.email         = ["jgitlin@pinnacle21.com"]

  spec.summary       = %q{Performs maintainence tasks on Artifactory repositories}
  spec.description   = %q{Will provide maintainence tasks for Artifactory, like cleaning up old artifacts}
  spec.homepage      = "https://bitbucket.org/pinnacle21/artifactory-cleaner/src/master/"
  spec.license       = 'MIT'
  spec.licenses      = ['MIT']
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  #spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  #spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://bitbucket.org/pinnacle21/artifactory-cleaner/src/master/"
  #spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."
  
  spec.add_development_dependency "cucumber", '~> 1.3', '>= 1.3.20'
  spec.add_development_dependency "aruba", '~> 0.14'
  spec.add_development_dependency "rdoc"

  spec.add_dependency "thor", '~> 1.0.1'
  spec.add_dependency "sysexits", '>= 1.2.0'

  spec.add_runtime_dependency "artifactory"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
