commentedOutCode: false positive for the example output oneliner
The following code in the file `gocritic_test.go` produces `commentedOutCode` false positive:
```go
package env_test

import "fmt"

func ExampleCommentedOutCode() {
	const c = "{Foo:a}"
	fmt.Printf("%v", c)
	// Output: {Foo:a}
}
```

```sh
❯ gocritic check -enable commentedOutCode gocritic_test.go
./gocritic_test.go:8:2: commentedOutCode: may want to remove commented-out code
```


Found in the `caarlos0/env` [repo](https://github.com/caarlos0/env/blob/a9fcfa336f5ca5d31788135b4a6c9b3375b06976/example_test.go#L354):

```sh
❯ gocritic check -enable commentedOutCode example_test.go
./example_test.go:353:2: commentedOutCode: may want to remove commented-out code
./example_test.go:391:2: commentedOutCode: may want to remove commented-out code
```
