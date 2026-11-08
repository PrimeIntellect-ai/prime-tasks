can't use unexported struct fields when converting using gno2go
This happens mostly when doing a "gonative" call, such as is the case for `(testing.T).Log`, or more generally `fmt.Sprintf`.

```go
package main

import "fmt"

type X struct {
        v string
}

func main() {
        fmt.Printf("test %#v", X{v: "a"})
}
```

```console
$ gno run a.gno
panic running expression main(): reflect: reflect.Value.SetString using value obtained using unexported field
```

My opinion is that in the long run we should aim to drop all the `gonative` opcodes and code; it appears to me that  `gonative` is mostly especially useful for "bootstrapping" functions in Gno, and is currently still useful mostly for functions like `fmt.Sprintf`, which would need to rely on reflection to work as expected.

However, to support use cases (such as mine, where I was trying to simply `t.Log` a struct) we may add a temporary fix to the problem.

On the patch/gnochess branch, [I changed this line](https://github.com/gnolang/gno/commit/b7644b465981ab23296616ca78de18a649a89c66#diff-50dc02426a13749bc9d1b34586db74f31088cf04c82a69b3ca03c5db2f7b684bL866) to make the struct field exported. This is a dirty trick, but it does the job:

```
$ gno run a.gno
test struct { Xv string }{Xv:"a"}%
```

Should a fix like this one be added to the main branch?

### Additional contract requirements

- When `fmt.Printf("test %#v\n", x)` formats `X{v: "a"}` where `X` has an unexported field `v string`, it must print exactly `test struct { v string }{v:"a"}`.
