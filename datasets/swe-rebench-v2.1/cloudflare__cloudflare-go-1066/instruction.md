Stream API wrong type
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

v0.48.0

### Go environment

GO111MODULE="on"
GOARCH="arm64"
GOBIN=""
GOCACHE="/Users/tomaz/Library/Caches/go-build"
GOENV="/Users/tomaz/Library/Application Support/go/env"
GOEXE=""
GOEXPERIMENT=""
GOFLAGS=""
GOHOSTARCH="arm64"
GOHOSTOS="darwin"
GOINSECURE=""
GOMODCACHE="/Users/tomaz/go/pkg/mod"
GONOPROXY=""
GONOSUMDB=""
GOOS="darwin"
GOPATH="/Users/tomaz/go"
GOPRIVATE=""
GOPROXY="https://proxy.golang.org,direct"
GOROOT="/opt/homebrew/Cellar/go/1.18.5/libexec"
GOSUMDB="sum.golang.org"
GOTMPDIR=""
GOTOOLDIR="/opt/homebrew/Cellar/go/1.18.5/libexec/pkg/tool/darwin_arm64"
GOVCS=""
GOVERSION="go1.18.5"
GCCGO="gccgo"
AR="ar"
CC="clang"
CXX="clang++"
CGO_ENABLED="1"
GOMOD="/Users/tomaz/GolandProjects/vpl_backend/go.mod"
GOWORK=""
CGO_CFLAGS="-g -O2"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-g -O2"
CGO_FFLAGS="-g -O2"
CGO_LDFLAGS="-g -O2"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -arch arm64 -pthread -fno-caret-diagnostics -Qunused-arguments -fmessage-length=0 -fdebug-prefix-map=/var/folders/2s/nnn7f20d4md80pjm0wdgdy340000gn/T/go-build3324721000=/tmp/go-build -gno-record-gcc-switches -fno-common"

### Expected output

Expected to get StreamVideo struct from the method.

### Actual output

json: cannot unmarshal string into Go struct field StreamVideoStatus.result.status.pctComplete of type int

### Code demonstrating the issue

api.StreamGetVideo(ctx, cloudflare.StreamParameters{
  AccountID: accountId,
  VideoID:   videoId,
})


### Steps to reproduce

api.StreamGetVideo(ctx, cloudflare.StreamParameters{
  AccountID: accountId,
  VideoID:   videoId,
})


### References

_No response_
