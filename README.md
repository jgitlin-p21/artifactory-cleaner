# Artifactory::Cleaner

[![Gem Version](https://badge.fury.io/rb/artifactory-cleaner.svg)](https://badge.fury.io/rb/artifactory-cleaner)
[![CircleCI](https://circleci.com/bb/pinnacle21/artifactory-cleaner.svg?style=svg&circle-token=da5970d1966d86b5fd6c37f70ad59bedbb66f3b4)](<LINK>)

Artifactory Cleaner is a tool for managing Artifactory repositories with a focus on analyzing and optimizing storage
usage within Artifactory. `Artifactory::Cleaner` can be used as a Gem inside other Ruby automation, and also includes
a command-line interface (CLI) which can be used inside an interactive terminal session or incorporated into other
automation workflows.

## Installation

### To use as a CLI command:

The gem can be installed using rubygems:

```bash
sudo gem install artifactory-cleaner
```

This will install the `artifactory-cleaner` command. 

Full usage information is available using `artifactory-cleaner help`

The `artifactory-cleaner` CLI interface follows the same format as git: `artifactory-cleaner command [options]`

Commands available are:

 * `artifactory-cleaner archive` Given a specific set of criteria (and optionally a set of filters) download all artifacts
   from specified repos to the local filesystem. *Note:* this will cause the `last_downloaded` date of all the artifacts
   which are archived to be updated to the time the command is run, so they may no longer match your search criteria on
   a subsequent run
 * `artifactory-cleaner clean` delete old artifacts which meet a specific set of criteria (and optionally a set of filters)
   from a given set of repos, with the ability to archive them to the local filesystem. This is Artifactory::Cleaner's 
   primry function: to reduce disk space usage by deleting old, unnecessary artifacts.
 * `artifactory-cleaner list-repos` provides information about available repositories in Artifactory. Can be used in
   pipelines with the `-H` flag, or can be used to query repository information in human-readable columns.
 * `artifactory-cleaner usage-report` analyze artifacts and produce a report detailing usage breakdown by date ranges,
   optionally producing a detailed YAML report of all artifacts meeting search criteria

#### Authentication and Configuration

In order for `artifactory-cleaner` to know which Artifactory server to communicate with and how to authenticate, either
command-line arguments may be used, or (preferably) a configuration filr may be specified using the `-c / --conf-file`
switch.

If using command line arguments, `--endpoint` can be used to specify the HTTPS URL of the Artifactory API, and `--api-key`
can be used to specify the API key. *Be aware* 

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

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests.
You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the 
version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, 
push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

