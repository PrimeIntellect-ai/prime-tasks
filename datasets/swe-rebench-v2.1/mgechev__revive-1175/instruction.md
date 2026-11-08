modifies-value-receiver: miss modification by `++`/`--`
**Describe the bug**
modifies-value-receiver does not trigger on `++` and `--`.

**To Reproduce**
Steps to reproduce the behavior:
1. I updated revive `go install github.com/mgechev/revive@latest`
2. I run it with the following flags & configuration file:

```shell
$ nl -ba main.go
     1	package main
     2
     3	import "fmt"
     4
     5	type Data struct {
     6		i int
     7	}
     8
     9	func (d Data) Inc() {
    10		d.i++
    11	}
    12
    13	func (d Data) IncBy(n int) {
    14		d.i += n
    15	}
    16
    17	func (d Data) Dec() {
    18		d.i--
    19	}
    20
    21	func (d Data) DecBy(n int) {
    22		d.i -= n
    23	}
    24
    25	func main() {
    26		var d Data
    27		d.Inc()
    28		d.IncBy(10)
    29		d.Dec()
    30		d.DecBy(5)
    31		fmt.Println(d)
    32	}
$ revive
main.go:14:2: suspicious assignment to a by-value method receiver
main.go:22:2: suspicious assignment to a by-value method receiver
$
```

```toml
[rule.modifies-value-receiver]
```

**Expected behavior**
```
main.go:10:2: suspicious assignment to a by-value method receiver
main.go:14:2: suspicious assignment to a by-value method receiver
main.go:18:2: suspicious assignment to a by-value method receiver
main.go:22:2: suspicious assignment to a by-value method receiver
```

**Desktop (please complete the following information):**
 - OS: Gentoo Linux
 - go version go1.23.2 linux/amd64
