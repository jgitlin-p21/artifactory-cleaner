# Artifactory::Cleaner

Artifactory Cleaner is a tool for managing Artifactory repositories with a focus on analyzing and optimizing storage
usage within Artifactory. `Artifactory::Cleaner` can be used as a Gem inside other Ruby automation, and also includes
a comamnd-line interface (CLI) which can be used inside an interactive terminal session or incorporated into other
automation workflows.

## Installation

### To use as a CLI command:

Check out the repo and execute: 

```bash
bundle install
gem build artifactory-cleaner.gemspec
sudo gem install artifactory-cleaner-*.gem
```

to install the `artifactory-cleaner` command. 

### To use as a gem:
Add this line to your application's Gemfile:

```ruby
gem 'artifactory-cleaner'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install artifactory-cleaner

## Usage

Execute `artifactory-cleaner help` for a usage statement

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

