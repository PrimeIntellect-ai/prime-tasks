traffic tags: Error if requested for removing non-existing tag
### Bug report
If requested to untag a non-existing tag in traffic block, add an error.

### Expected behavior
`service update` command returns error message indicating the tag doesnt exists for service and non-zero exit status.

### Steps to reproduce the problem
1. `kn service create hello --image knativesamples/helloworld`
2. `kn service update hello --untag foo --no-wait`

### kn version
latest

### Knative (serving/eventing) version
v0.15.0

### Additional contract requirements

- For `--untag foo`, the `service update` error output must contain the substrings `tag(s)`, `foo`, `not present`, `service`, and the service name.
