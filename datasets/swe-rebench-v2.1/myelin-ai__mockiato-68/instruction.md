Change wording if no calls were expected
Replace `The following calls were expected:` with `No calls were expected`

### Additional contract requirements

When a call is made that was not expected and no calls at all were expected for that method, the panic message must contain a line stating that no calls to that mock method were expected. This method-qualified line replaces the expected-calls heading; it is not followed by a separate generic `No calls were expected` line. For example, for a mock `GreeterMock` whose method is `greet`, the message contains `No calls to GreeterMock::greet were expected.`

- For the `GreeterMock::greet` call with argument `"John"` when no calls were expected, the panic message must contain `The call ("John",) was not expected.` immediately followed by `No calls to GreeterMock::greet were expected.`
