Attempts to create a pool with 0 origins will always fail
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

v0.72.0

### Go environment

GO111MODULE=""
GOARCH="arm64"
GOBIN=""
GOCACHE="/Users/kelvin/Library/Caches/go-build"
GOENV="/Users/kelvin/Library/Application Support/go/env"
GOEXE=""
GOEXPERIMENT=""
GOFLAGS=""
GOHOSTARCH="arm64"
GOHOSTOS="darwin"
GOINSECURE=""
GOMODCACHE="/Users/kelvin/go/pkg/mod"
GONOPROXY=""
GONOSUMDB=""
GOOS="darwin"
GOPATH="/Users/kelvin/go"
GOPRIVATE=""
GOROOT="/opt/homebrew/Cellar/go/1.20.5/libexec"
GOSUMDB="off"
GOTMPDIR=""
GOTOOLDIR="/opt/homebrew/Cellar/go/1.20.5/libexec/pkg/tool/darwin_arm64"
GOVCS=""
GOVERSION="go1.20.5"
GCCGO="gccgo"
AR="ar"
CC="cc"
CXX="c++"
CGO_ENABLED="1"
GOWORK=""
CGO_CFLAGS="-O2 -g"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-O2 -g"
CGO_FFLAGS="-O2 -g"
CGO_LDFLAGS="-O2 -g"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -arch arm64 -pthread -fno-caret-diagnostics -Qunused-arguments -fmessage-length=0 -fdebug-prefix-map=/var/folders/z1/4lpjdpw96m12m3xgtvvl3m1r0000gn/T/go-build158583462=/tmp/go-build -gno-record-gcc-switches -fno-common"

### Expected output

Pool created successfully

### Actual output

error: the minimum_origins must be in range [1, 0]: validation failed (1002)


### Code demonstrating the issue
```
package main

import (
	"context"
	"fmt"
	"github.com/cloudflare/cloudflare-go"
)

func main() {
	api, err := cloudflare.New("<redacted>", "<redacted>")
	if err != nil {
		panic(err)
	}
	accountId := cloudflare.AccountIdentifier("<redacted>")
	testPool := cloudflare.LoadBalancerPool{
		Description:    "Primary data center - Provider XYZ",
		Name:           "primary-dc-1",
		Enabled:        true,
		MinimumOrigins: 0,
		Origins:        []cloudflare.LoadBalancerOrigin{},
	}
	createPoolParams := cloudflare.CreateLoadBalancerPoolParams{LoadBalancerPool: testPool}
	pool, err := api.CreateLoadBalancerPool(context.Background(), accountId, createPoolParams)
	if err != nil {
		panic(err)
	}
	fmt.Printf("pool: %+v\n", pool)
}
```

### Steps to reproduce

Create a pool with no origins and MinimumOrigins set to 0

### References

_No response_
