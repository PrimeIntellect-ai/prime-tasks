Catching invalid step functions
**Is your feature request related to a problem? Please describe.**
Currently `suite.AddStep` returns an error which I could check if I want to handle invalid step definitions. This is a bit counterintuitive, because I certainly don't want to check them one by one.

**Describe the solution you'd like**
Ideally, the framework should probably check all step functions at once when calling `suite.Run`. I would like to see all invalid functions.

If it already does, then I would remove the returned error from `suite.AddStep` to have a cleaner API.

**Describe alternatives you've considered**
Add a `suite.MustAddStep` that terminates the test (`*testing.T` is already available at this point), but I think it would be better to see all invalid step functions.

### Additional contract requirements

- `Suite.AddStep(expr string, step interface{})` returns no value. A step definition whose function signature is invalid is recorded and reported when `Run` is called.
- `NewSuite` accepts a testing abstraction that provides `Log(...interface{})`, `Fatal(...interface{})`, `Fatalf(string, ...interface{})`, `Parallel()`, `Fail()`, and `Run(name string, f func(t *testing.T)) bool`.
- When `Run` is called and one or more registered step definitions have an invalid signature, every invalid definition is reported individually through the testing abstraction's `Log` method, and the run is aborted.
