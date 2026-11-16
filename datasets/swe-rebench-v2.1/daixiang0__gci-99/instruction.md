Duplicate imports are reordered back and forth (`gci write` not idempotent)
I am using gci to format [this Go file](https://github.com/juju/juju/blob/41a6baeb0c4c6c76891847aa72deb08f44aacd4e/cmd/juju/romulus/sla/sla_test.go). Note that it has duplicate imports:
```go
import (
        ...
	"github.com/juju/testing"
	jujutesting "github.com/juju/testing"
        ...
)
```
When I run
```
gci write -s standard -s default -s "Prefix(github.com/juju/juju)" --skip-generated \
  cmd/juju/romulus/sla/sla_test.go
```
it will continue to reorder these imports. i.e. after one run they will be in the reverse order
```go
import (
        ...
	jujutesting "github.com/juju/testing"
	"github.com/juju/testing"
        ...
)
```
If I run it again, they will return to the original order. If I run it again, they will reverse again, and so forth.

This is observed on gci v0.6.2. Obviously I would expect `gci write` to be idempotent. I am struggling to isolate a MWE - I've tried a few simpler Go files and haven't observed this behaviour.

### Additional contract requirements

- When the same import path appears both without an alias and with alias `a`, place the unaliased import first: `"github.com/daixiang0/gci"` before `a "github.com/daixiang0/gci"`.
