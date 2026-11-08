[BUG] <Access API Error after upgrading fcl-js>
### Current Behavior

The problem we're seeing happenes right after we upgraded fcl-js sdk to latest stable version:
```
@onflow/fcl": "1.9.0"   ->  "1.10.0"
@onflow/transport-http": "^1.9.0"   -> "1.10.0"
@onflow/transport-grpc": "1.3.1"    ->  "1.4.0"
```

The access node provider we're using is Quicknode, e.g.: https://dawn-wild-valley.flow-mainnet.quiknode.pro/4beb5df392b61695757c57d6b82474193c427fb5/


* Request after upgrade:
```
Request URL:
https://dawn-wild-valley.flow-mainnet.quiknode.pro/v1/accounts/a886e89209bca080?block_height=sealed&expand=contracts,keys
Request Method:
GET
Status Code:
401 Unauthorized
Remote Address:
64.31.42.222:443
Referrer Policy:
strict-origin-when-cross-origin
```

* Comparing with previous version and expected behavior below you can see that the API token in the access url is gone, suspecting it to be some url parsing bug introduced between versions.


### Expected Behavior

* Request before update:
```
Request URL:
https://dawn-wild-valley.flow-mainnet.quiknode.pro/4beb5df392b61695757c57d6b82474193c427fb5/v1/accounts/a886e89209bca080?block_height=sealed&expand=contracts,keys
Request Method:
GET
Status Code:
200 OK
Remote Address:
64.31.42.222:443
Referrer Policy:
strict-origin-when-cross-origin
```

### Steps To Reproduce

```
@onflow/fcl": "1.9.0"   ->  "1.10.0"
@onflow/transport-http": "^1.9.0"   -> "1.10.0"
@onflow/transport-grpc": "1.3.1"    ->  "1.4.0"
```

Nothing else changed. (Though Quicknode endpoints come with hostname whitelists, `localhost:1024` is one within the whitelist for test.)

### Environment

```markdown
- OS: MacOS 14.4.1 (23E224)
- Node: 16.20.2
- npm: 8.19.4
```


### What are you currently working on that this is blocking?

It may affect app.increment.fi and other Dapps using QuickNode rpc service.

### Additional contract requirements

- Add a public function `combineURLs(baseURL: string, relativeURL?: string): string` in module `packages/transport-http/src/combine-urls.ts`. When `relativeURL` is omitted, it returns `baseURL` unchanged. When `relativeURL` is supplied, it returns the two joined with exactly one slash between them, stripping trailing slashes from `baseURL` and leading slashes from `relativeURL` as needed.
- The HTTP request helper `httpRequest` in `packages/transport-http/src/http-request.js` accepts an options object with `hostname`, `path` and `method` (plus optional `body`, `headers`, retry and timeout options) and issues the request to the URL formed from `hostname` and `path`. Any path already present in `hostname` must be preserved in the resulting request URL.
