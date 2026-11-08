Add support for "getline lvalue"
Currently we support most getline forms, but not `getline lvalue`. For example, see the commented-out tests in `interp/interp_test.go`:

```
		// TODO: currently we support "getline var" but not "getline lvalue"
		// TODO: {`BEGIN { getline a[1]; print a[1] }`, "foo", "foo\n", "", ""},
		// TODO: {`BEGIN { getline $1; print $1 }`, "foo", "foo\n", "", ""},
```

### Additional contract requirements

- Values read by `getline` must retain numeric-string semantics: with input `0.0`, the values in `$0` after `getline` and in `x` after `getline x` must compare equal to numeric `0`, so `print($0==0)` and `print(x==0)` each print `1`. This must also hold when reading through a pipe.
