Access application custom attributes don't update when removed
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

v0.101.0

### Go environment

```text
GO111MODULE=''
GOARCH='arm64'
GOBIN=''
GOCACHE='/Users/mprovost/Library/Caches/go-build'
GOENV='/Users/mprovost/Library/Application Support/go/env'
GOEXE=''
GOEXPERIMENT=''
GOFLAGS=''
GOHOSTARCH='arm64'
GOHOSTOS='darwin'
GOINSECURE=''
GOMODCACHE='/Users/mprovost/go/pkg/mod'
GONOPROXY=''
GONOSUMDB=''
GOOS='darwin'
GOPATH='/Users/mprovost/go'
GOPRIVATE=''
GOPROXY='https://proxy.golang.org,direct'
GOROOT='/opt/homebrew/Cellar/go/1.22.5/libexec'
GOSUMDB='sum.golang.org'
GOTMPDIR=''
GOTOOLCHAIN='auto'
GOTOOLDIR='/opt/homebrew/Cellar/go/1.22.5/libexec/pkg/tool/darwin_arm64'
GOVCS=''
GOVERSION='go1.22.5'
GCCGO='gccgo'
AR='ar'
CC='cc'
CXX='c++'
CGO_ENABLED='1'
GOMOD='/Users/mprovost/Projects/go-repro/go.mod'
GOWORK=''
CGO_CFLAGS='-O2 -g'
CGO_CPPFLAGS=''
CGO_CXXFLAGS='-O2 -g'
CGO_FFLAGS='-O2 -g'
CGO_LDFLAGS='-O2 -g'
PKG_CONFIG='pkg-config'
GOGCCFLAGS='-fPIC -arch arm64 -pthread -fno-caret-diagnostics -Qunused-arguments -fmessage-length=0 -ffile-prefix-map=/var/folders/zn/gmcgtk3s26xc8x7d4s2z43hw0000gn/T/go-build358138541=/tmp/go-build -gno-record-gcc-switches -fno-common'
```

### Expected output

Custom attributes should be removed when an empty list is passed as the custom attributes.

### Actual output

Nothing changes, since the attribute is omitted when empty:

https://github.com/cloudflare/cloudflare-go/blob/80d52bc4aa257a198d85177a11722407797c9705/access_application.go#L233

### Code demonstrating the issue

```go
package main

import (
	"context"
	"log"
	"os"

	"github.com/cloudflare/cloudflare-go"
)

func main() {
	api, err := cloudflare.New(os.Getenv("CLOUDFLARE_API_KEY"), os.Getenv("CLOUDFLARE_EMAIL"))
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()

	accountId := "<Account ID>"
	applicationId := "<Application ID>"

	account := cloudflare.AccountIdentifier(accountId)

	application := cloudflare.UpdateAccessApplicationParams{
		ID:   applicationId,
		Name: "TESTING",
		Type: "saas",
		SaasApplication: &cloudflare.SaasApplication{
			CustomAttributes: []cloudflare.SAMLAttributeConfig{},
		},
	}

	newApplication, err := api.UpdateAccessApplication(ctx, account, application)
	if err != nil {
		log.Fatal(err)
	}

	log.Print(newApplication)
}
```

### Steps to reproduce

1. Create an Access application
   - Saas type
   - SAML authentication (the application in this step doesn't matter)
   - Add a SAML attribute statement. It doesn't matter the contents, nor any other information in this step
   - The rest of the data is irrelevant and can be set to anything
2. Fill in the repro code with the proper account ID and application ID
3. Run the repro
4. Notice in the dashboard that the custom attribute statement wasn't removed

### References

_No response_
