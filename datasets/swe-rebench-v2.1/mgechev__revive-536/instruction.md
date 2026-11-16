import-shadowing shouldn't check current package name
**Describe the bug**
```go
// File: github.com/powerman/go-monolith-example/ms/auth/internal/config/config.go
package config
import "github.com/powerman/go-monolith-example/internal/config"
```
```
ms/auth/internal/config/config.go:11:9: import-shadowing: The name 'config' shadows an import name (revive)
package config
        ^
```

**To Reproduce**
I use revive bundled with golangci-lint 1.41.1.

**Expected behavior**
Within package named "x" we should be able to import/create identifiers with same name "x" - there is no shadowing in this case.

**Desktop (please complete the following information):**
 - OS: Gentoo Linux
 - go version go1.16.5 linux/amd64
