GHIssueStateReason should add reopened
While going against a repository I am involved with, I recieved this message in the console:
````
org.kohsuke.github.internal.EnumUtils getEnumOrDefault
WARNING: Unknown value reopened for enum class org.kohsuke.github.GHIssueStateReason, defaulting to UNKNOWN
````
Would be best if it was added for proper recognition.

### Additional contract requirements

- The new enum constant is named exactly `REOPENED`.
- The value `reopened` (as returned by GitHub) is recognized and resolves to `GHIssueStateReason.REOPENED` instead of defaulting to `UNKNOWN`.
