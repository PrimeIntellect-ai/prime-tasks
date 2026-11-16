suite: WithStats incorrect for tests that panic
Hey!

First, thanks for maintaining the lib.

I've stumbled upon an issue when using https://pkg.go.dev/github.com/stretchr/testify/suite#WithStats. It seems that tests that panic are marked as `Passed` even though they fail and they are are failures for `go test`.

repro:
```golang

package m

import (
	"fmt"
	"testing"
	"github.com/stretchr/testify/suite"
)

type ExampleTestSuite struct {
    suite.Suite
}

func (suite *ExampleTestSuite) HandleStats(suiteName string, stats *suite.SuiteInformation) {
	fmt.Printf("Test passed? %t\n", stats.TestStats["TestExample"].Passed)
}

func (suite *ExampleTestSuite) TestExample() {
	panic("x")
}

func TestExampleTestSuite(t *testing.T) {
    suite.Run(t, new(ExampleTestSuite))
}
```

output:

```
$ go test
Test passed? true
--- FAIL: TestExampleTestSuite (0.00s)
    --- FAIL: TestExampleTestSuite/TestExample (0.00s)
        suite.go:63: test panicked: x
            goroutine 20 [running]:
            runtime/debug.Stack()
            	/usr/local/go/src/runtime/debug/stack.go:24 +0x65
            github.com/stretchr/testify/suite.failOnPanic(0xc00011e4e0)
            	/Users/nicolas/go/pkg/mod/github.com/stretchr/testify@v1.7.0/suite/suite.go:63 +0x3e
            panic({0x132be20, 0x1414228})
            	/usr/local/go/src/runtime/panic.go:838 +0x207
            example.com/m.(*ExampleTestSuite).TestExample(0x0?)
            	/Users/nicolas/playground/m_test.go:18 +0x27
            reflect.Value.call({0xc0000a5140?, 0xc0000a2cc0?, 0x13?}, {0x138c249, 0x4}, {0xc000055e70, 0x1, 0x1?})
            	/usr/local/go/src/reflect/value.go:556 +0x845
            reflect.Value.Call({0xc0000a5140?, 0xc0000a2cc0?, 0x1310d3f?}, {0xc000042670, 0x1, 0x1})
            	/usr/local/go/src/reflect/value.go:339 +0xbf
            github.com/stretchr/testify/suite.Run.func1(0xc00011e4e0)
            	/Users/nicolas/go/pkg/mod/github.com/stretchr/testify@v1.7.0/suite/suite.go:158 +0x4b6
            testing.tRunner(0xc00011e4e0, 0xc0000f2090)
            	/usr/local/go/src/testing/testing.go:1439 +0x102
            created by testing.(*T).Run
            	/usr/local/go/src/testing/testing.go:1486 +0x35f
FAIL
exit status 1
FAIL	example.com/m	0.169s
```

[HIDDEN]

Let me know if this looks like a legit bug to you or not; I'd be happy to contribute with a fix!

### Additional contract requirements

- When a suite test panics, `WithStats` must report that test as not passed in its per-test statistics.
