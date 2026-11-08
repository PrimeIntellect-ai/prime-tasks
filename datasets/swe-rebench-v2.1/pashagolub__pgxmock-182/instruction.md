pgxmock.ExpectBegin is not documented
I expected to see it in the **Functions** section at
https://pkg.go.dev/github.com/pashagolub/pgxmock/v3#pkg-functions
but only `NewResult` and `QueryMatcherOption` are listed here.

I can't find it anywhere else in the documentation, either.

(BTW., thanks for a really helpful module!)

### Additional contract requirements

- Package `pgxmock` must export an interface type named `Expecter` that declares `ExpectBegin() *ExpectedBegin`, so that `ExpectBegin` is discoverable in the package's public API documentation.
