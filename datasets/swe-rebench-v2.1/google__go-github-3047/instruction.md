UploadSarif Always Returns An Error
In version 57.0.0 of go-github, [UploadSarif](https://github.com/google/go-github/blob/v57.0.0/github/code-scanning.go#L384) never returns a valid SarifID object [HIDDEN] because [this endpoint](https://docs.github.com/en/rest/code-scanning/code-scanning?apiVersion=2022-11-28#upload-an-analysis-as-sarif-data) returns a 202. It seems to exhibit the same behavior that was fixed for CreateFork in #878.

### Additional contract requirements

- When the upload endpoint returns HTTP 202 with a SarifID in the response body, UploadSarif must return that SarifID without an error.
