Wrong import path generated for an operation called "client"
## Problem statement
I have a set of operations under a tag called "client". When I go to generate my server code in an output folder called `gen/server`, the file at `gen/server/restapi/operations/<app_name>_api.go` has all the correct operation imports, EXCEPT for the one called client.

The imports for all the others look like:

```go
	"github.com/<org name>/<app name>/gen/server/restapi/operations/budgets"
```

But the import for the client operations looks like:
```go
	"github.com/<org name>/<app name>/gen/server/client"
```

The `restapi/operations` part of the path is missing.

If I rename the tag to `client2`, this behavior is not reproduced.

Please remove the sections that don't apply

## Swagger specification
N/A

## Steps to reproduce
Explained above

## Environment
swagger version: v0.28.0 and v0.29.0 have same behavior
go version: go1.17.5
OS: mac osx monterey
