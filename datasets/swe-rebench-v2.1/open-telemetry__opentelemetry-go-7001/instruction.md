log: Add Record.Clone
This is of type `go.opentelemetry.io/otel/log.Record` not `go.opentelemetry.io/otel/sdk/log.Record`

_Originally posted by @Mojachieee in https://github.com/open-telemetry/opentelemetry-go/pull/6968#discussion_r2194485774_

Implement `Record.Clone` in the same way as

https://github.com/open-telemetry/opentelemetry-go/blob/afd476363f2bc3b2f9ff8168a16400959c7f07a0/sdk/log/record.go#L402-L408
