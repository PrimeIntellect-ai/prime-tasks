import-shadowing reacts on method names while it shouldn't
**Describe the bug**
`import-shadowing` rule marks method names as shadowing, but it's not a true shadowing since it's a part of a struct. I'm not sure if it was done intentionally or not, but it seems to be a bug.

**To Reproduce**

```go
package somepkg

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"
)

type Struct struct{}

func (s *Struct) reconcile(md metav1.ObjectMeta) (reconcile.Result, error) {
	return reconcile.Result{}, nil
}
```

Run revive against this file and get this (I use `golangci-lint`, but I guess it's a problem in revive itself):

```
somepkg/t.go:10:18: import-shadowing: The name 'reconcile' shadows an import name (revive)
func (s *Struct) reconcile(md metav1.ObjectMeta) (reconcile.Result, error) {
                 ^
```

**Expected behavior**
It should not consider method names as a shadow for the imported packages. Only package-level functions (i.e. not methods) should be considered.

**Additional context**
I use `golangci-lint` [v1.54.2](https://github.com/golangci/golangci-lint/releases/tag/v1.54.2).
