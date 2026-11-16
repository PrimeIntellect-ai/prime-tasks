Structured logging behaviour changed from v2.0.0 to v2.1.0
/kind bug

Structured logging using levelled V function changed.

**What steps did you take and what happened:**
Create test program
`$ go mod init klogtest`
```golang
package main

import (
	"k8s.io/klog/v2"
)

func main() {
	klog.InitFlags(nil)
	klog.InfoS("Hello1", "msg", "without V")
	klog.V(0).InfoS("Hello2", "msg", "message with V(0)")
}
```

Output:
```
$ grep klog go.mod
	k8s.io/klog/v2 v2.1.0
$ go run .
I0614 15:19:37.239517  118778 main.go:9] "Hello1" msg="without V"
I0614 15:19:37.239593  118778 main.go:10] "Hello2" [msg message with V(0)]="(MISSING)"
```

**What did you expect to happen:**
Change the version back to v2.0.0 in the `go.mod` file and run again:
```
$ grep klog go.mod
	k8s.io/klog/v2 v2.0.0
$ go run .
I0614 15:19:45.638733  118902 main.go:9] "Hello1" msg="without V"
I0614 15:19:45.638838  118902 main.go:10] "Hello2" msg="message with V(0)"
```
