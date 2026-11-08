ListDNSRecords overwrites proxied value when paginated
### Confirmation

- [X] My issue isn't already found on the issue tracker.
- [X] I have replicated my issue using the latest version of the library and it is still present.

### cloudflare-go version

0.61.0

### Go environment

GO111MODULE=""
GOARCH="amd64"
GOBIN=""
GOCACHE="/home/vscode/.cache/go-build"
GOENV="/home/vscode/.config/go/env"
GOEXE=""
GOEXPERIMENT=""
GOFLAGS=""
GOHOSTARCH="amd64"
GOHOSTOS="linux"
GOINSECURE=""
GOMODCACHE="/go/pkg/mod"
GONOPROXY=""
GONOSUMDB=""
GOOS="linux"
GOPATH="/go"
GOPRIVATE=""
GOPROXY="https://proxy.golang.org,direct"
GOROOT="/usr/local/go"
GOSUMDB="sum.golang.org"
GOTMPDIR=""
GOTOOLDIR="/usr/local/go/pkg/tool/linux_amd64"
GOVCS=""
GOVERSION="go1.20"
GCCGO="gccgo"
GOAMD64="v1"
AR="ar"
CC="gcc"
CXX="g++"
CGO_ENABLED="1"
GOMOD="/workspaces/dangling-dns-checker/go.mod"
GOWORK=""
CGO_CFLAGS="-O2 -g"
CGO_CPPFLAGS=""
CGO_CXXFLAGS="-O2 -g"
CGO_FFLAGS="-O2 -g"
CGO_LDFLAGS="-O2 -g"
PKG_CONFIG="pkg-config"
GOGCCFLAGS="-fPIC -m64 -pthread -Wl,--no-gc-sections -fmessage-length=0 -fdebug-prefix-map=/tmp/go-build2684787559=/tmp/go-build -gno-record-gcc-switches"

### Expected output

When listing the DNS records for a zone that has sufficient records as to require pagination, the Proxied field on all the DNS records returned match that shown on the web portal.

### Actual output

As subsequent pages are fetched from the API, the values for the Proxied field from the latest page overwrites the values in the records from the previous pages.

For example, say you have 8 records and a page size of 3, looking at just the Proxied field the records might be:
1. true
2. false
3. true
4. true
5. true
6. false
7. false
8. false

The API returns the correct values, however, the returned values for ListDNSRecords would be
1. false
2. false
3. false
4. false
5. false
6. false
7. false
8. false

[HIDDEN]

I hope that is a clear enough explanation, but happy to explain further if not.

### Code demonstrating the issue

token := "<api-token>"
zone := "<zone-name>" // Use zone with >100 records
api, err := cloudflare.NewWithAPIToken(token)
if err != nil {
  log.Fatalf("failed to log into cloudflare: %v\n", err)
}
id, _ := api.ZoneIDByName(zone)
ctx := context.Background()
resouces := cloudflare.ZoneIdentifier(id)
opts := cloudflare.ListDNSRecordsParams{}
records, _, _ := api.ListDNSRecords(ctx, resouces, opts)

for idx, record := range records {
  if record.Proxied != nil {
    log.Printf("%d: %v %s\n", idx, *record.Proxied, record.Name)
  }
}


### Steps to reproduce

1. Have a DNS zone with over 100 record with various records set to Proxied/Not Proxied
2. Setup api client and call ListDNSRecords with default options
3. Observe the returned result's `Proxied` field is repeating pattern as described in Actual output

### References

I have forked the repo and have created a potential fix:
https://github.com/MrMortbury/cloudflare-go/tree/master

I also updated the TestListDNSRecordsPagination in `dns_test.go` to test for this situation and validate the records returned by the client matches that returned by the HTTP requests:
https://github.com/MrMortbury/cloudflare-go/blob/master/dns_test.go#L348

### Additional contract requirements

- When `ListDNSRecords` returns records spanning multiple pages, each record's `Proxied` field must match the value supplied by the API for that specific record, independent of values on other pages.
