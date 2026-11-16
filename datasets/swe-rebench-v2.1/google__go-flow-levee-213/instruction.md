Enforce strict config unmarshalling
In order to minimize the risk of configuration errors, we would like the unmarshalling of the configuration to be strict. Specifically, it should disallow unknown fields in matchers. This avoids errors where a typo in a key name leads to an incorrect configuration. We don't want typos to lead to silent failures, e.g. a matcher is broken and the user thinks their code is safe when it is not.

There are already two test cases covering this behavior to some extent, in `config/matcher_test.go`:

```go
		{
			desc: "Unmarshaling is strict",
			yaml: `
Blahblah: foo
PackageRE: bar`,
			shouldErrorOnLoad: false, // TODO true
		},
```

(It is the same case, in the tests for two different matchers.)
