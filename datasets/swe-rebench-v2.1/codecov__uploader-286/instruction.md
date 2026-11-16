Upload from travis-ci.com fails to detect service
**Describe the bug**
Following the instructions [here](https://docs.codecov.com/docs/codecov-uploader) in my travis-ci.com build, uploading the coverage report fails with an error about "Unable to detect service".

**To Reproduce**
Steps to reproduce the behavior:
1. Visit https://travis-ci.com/github/tagatac/bagoup/builds/234787055
2. Click on the arrow next to line 296.
3. Scroll down to line 337
4. See error "Unable to detect service, please specify manually."

**Expected behavior**
codecov uploads the coverage report without issue.

**Additional context**
Makefile target that generates this error at the commit that triggered the build referenced above: https://github.com/tagatac/bagoup/blob/14d7c0cb2349754a7f777f3abb50f90d43c9d313/Makefile#L36-L44
