If a matcher panics and AssertExpectations has been deferred, a hang occurs
In the code below, the test case TestMatcherPanic hangs. To reproduce the hang, two conditions must be met:
1. AssertExpectations is deferred
2. An argument matcher panics

```
import (
	"testing"

	"github.com/stretchr/testify/mock"
)

type Mock struct {
	mock.Mock
}

func (_m *Mock) F() {
	_m.Called()
}

func TestMatcherPanic(t *testing.T) {
  m := &Mock{}
  defer m.AssertExpectations(t)

  matcher := mock.MatchedBy(func(_ interface{}) bool {
    panic("test")
  })
  m.On("F", matcher)

  m.F()
}
```
