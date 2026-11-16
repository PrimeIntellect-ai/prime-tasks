CLI: Listing assessment results does not contain `compliant` field
**Describe the bug**
When using the CLI command to list assessment results, all fields but `compliant` will be printed.

**To Reproduce**
Steps to reproduce the behavior:
1. Prep:
   -  `go generate ./...`
   - `go install cmd/cli/cl.go`
2. Run engine: `clouditor.io/clouditor/cmd/engine --db-in-memory`
3. Start discovery (and thus, assessment as well): `cl discovery start`
4. List assessment results: `cl assessment list`

**Output snippet**
 ```
{
      "id":  "b3e65116-064e-433b-b1ad-e20dbde36f92",
      "timestamp":  "2021-12-15T10:07:35.002764902Z",
      "metricId":  "BootLoggingOutput",
      "metricData":  {},
      "evidenceId":  "XXX",
      "resourceId":  "XXX",
      "nonComplianceComments":  "No comments so far"
 }
```


**Expected behavior**
`compliant` field should be also included:
<pre>
{
      "id":  "b3e65116-064e-433b-b1ad-e20dbde36f92",
      "timestamp":  "2021-12-15T10:07:35.002764902Z",
      "metricId":  "BootLoggingOutput",
      "metricData":  {},
      <b>"compliant":  true/false,</b>
      "evidenceId":  "XXX",
      "resourceId":  "XXX",
      "nonComplianceComments":  "No comments so far"
 }
</pre>
