gradle-plugin: problems with the new `githubActions` mode
## Expected behavior
SARIF report can be identified by `.sarif` extension

## Observed behavior
https://github.com/analysis-dev/diktat/commit/0698727bcf762ce7a765098dcf36be5cebcca6a1#diff-52618882223ec0dcf8f8568e2158fd7d1f83502da075d9658d3b5e24d92f7d0fR162
SARIF report has the same name, as the project. It makes it really hard to automatically discover these reports.

## Environment information
* diktat version: 1.0.3
* build tool (maven/gradle): gradle
