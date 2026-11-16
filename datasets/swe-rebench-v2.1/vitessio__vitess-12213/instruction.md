Feature Request: ability to remove a registered vtgateconn dialer
### Feature Description

As of now, the Go `vitessdriver` package will register in a new dialer each time you specify a new Protocol name in the configuration. This means that ultimately an unbounded number of dialers will continue to accumulate throughout the lifetime of an application, unless you reuse the same name(s) repeatedly.

Being able to remove a dialer from the list means that it is possible for many unique dial configurations to be used throughout the lifetime of a program, while also keeping memory use in check.

### Use Case(s)

Programs which open a large number of vtgate dialer connections with differing gRPC dial option configurations over their lifetime.

### Additional contract requirements

- Add a public function `DeregisterDialer(name string)` in package `vitess.io/vitess/go/vt/vtgate/vtgateconn` that removes the dialer previously registered under `name`.
- After a dialer is removed, calling `DialProtocol` with that protocol returns the error `no dialer registered for VTGate protocol <name>`.
- If `name` is not registered, the call is a no-op: it does not panic and does not affect any other registered dialer.
