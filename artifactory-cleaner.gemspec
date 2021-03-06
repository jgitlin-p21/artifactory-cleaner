# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require_relative 'lib/artifactory/cleaner/version'

Gem::Specification.new do |spec|
  spec.name          = "artifactory-cleaner"
  spec.version       = Artifactory::Cleaner::VERSION
  spec.authors       = ["Josh Gitlin"]
  spec.email         = ["jgitlin@pinnacle21.com"]

  spec.summary       = %q{Performs maintenance tasks on Artifactory repositories}
  spec.description   = <<~END_OF_SPEC_DESCRIPTION
    `artifactory-cleaner` is a Ruby Gem and CLI interface for performing maintenance tasks on a JFrog Artifactory
    instance. It is capable of analyzing storage usage and producing reports showing space usage based on artifact age.
    It can then archive and delete from artifactory repos based on age/last download date with a highly configurable
    inclusion/exclusion list.
  END_OF_SPEC_DESCRIPTION
  spec.homepage      = "https://github.com/jgitlin-p21/artifactory-cleaner"
  spec.license       = 'MIT'
  spec.licenses      = ['MIT']
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://bitbucket.org/pinnacle21/artifactory-cleaner/src/master/"
  spec.metadata["changelog_uri"] = "https://raw.githubusercontent.com/jgitlin-p21/artifactory-cleaner/master/CHANGELOG.md"
  
  spec.add_development_dependency "cucumber", '~> 1.3', '>= 1.3.20'
  spec.add_development_dependency "aruba", '~> 0.14'
  spec.add_development_dependency "rdoc"

  spec.add_dependency "thor", '~> 1.0.1'
  spec.add_dependency "sysexits", '>= 1.2.0'

  spec.add_dependency "artifactory", '~> 3.0.15'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
