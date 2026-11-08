Uploads to Service Travis CI Fail With Status Code 400
**Describe the bug**
Uploads to Travis CI fail.

**To Reproduce**
1. Go to https://travis-ci.com/github/tagatac/bagoup/builds/235325025#L340
2. Click on the arrow next to line 296
3. Scroll down to line 340
4. See error `Error uploading to Codecov when fetching PUT (inner): 400 Invalid request parameters`

**Expected behavior**
The coverage report is uploaded and processed without issue.

**Additional context**
See for comparison a successful upload of the same report, disguised as a local CI provider by unsetting the environment variable `CI`: https://travis-ci.com/github/tagatac/bagoup/builds/235324541

Note in the failing example `pr=NaN` could be problematic.
