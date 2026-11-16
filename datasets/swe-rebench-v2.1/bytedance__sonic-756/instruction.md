Bugs when marshal nil interface{} that contains not-indirect values
**Describe the bug**

as title

**To Reproduce**

```
package issue_test

import (
	"testing"
	"github.com/bytedance/sonic"
)



func TestIssue755(t *testing.T) {
	tests := []interface{} {
		struct {
			Foo *int
		}{},
		struct {
			Foo func()
		}{},
		chan int(nil),
	}
	for _, v := range(tests) {
		assertMarshal(t, sonic.ConfigDefault, v)
	}
}
```

**Expected behavior**


**Screenshots**

```
Begin GC looping...
=== RUN   TestIssue755_
    common_test.go:37:
            Error Trace:    /home/liuqiang.06/sonic/issue_test/common_test.go:37
                                        /home/liuqiang.06/sonic/issue_test/issue755_test.go:15
            Error:          Not equal:
                            expected: []byte{0x7b, 0x22, 0x46, 0x6f, 0x6f, 0x22, 0x3a, 0x6e, 0x75, 0x6c, 0x6c, 0x7d}
                            actual  : []byte{0x6e, 0x75, 0x6c, 0x6c}

                            Diff:
                            --- Expected
                            +++ Actual
                            @@ -1,3 +1,3 @@
                            -([]uint8) (len=12) {
                            - 00000000  7b 22 46 6f 6f 22 3a 6e  75 6c 6c 7d              |{"Foo":null}|
                            +([]uint8) (len=4) {
                            + 00000000  6e 75 6c 6c                                       |null|
                             }
            Test:           TestIssue755_
            Messages:       {Foo:<nil>}
--- FAIL: TestIssue755_ (0.00s)
FAIL
FAIL    github.com/bytedance/sonic/issue_test   0.021s
FAIL
```

**Sonic version:**

sonic v1.12.9
