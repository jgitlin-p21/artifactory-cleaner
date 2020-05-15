Artifactory Cleaner CHANGELOG
=============================
This file describes the changes made in each release of `artifactory-cleaner`

## v1.0.3 (May 15, 2020)

 - Fix thread deadlocks which occured if exceptions were raised in the discovery worker threads
 - Update to `artifactory-client` 3.0.13 to avoid verbose warnings about deprecated `URI` methods
 
 
## v1.0.2 (February 25, 2020)

 - Fix circular dependency between bundler and gem install
 

## v1.0.1 (February 09, 2020)

 - Initial Public Release