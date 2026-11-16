exitAfterDefer: false positive
Using latest golangci-lint, found something which looks like false positive
Possibly related: #995

```go
        var Response *http.Response
	if Response, Error = client.Do(Request); Error == nil {
		defer Response.Body.Close()
	} else {
		fmt.Println("[client.Do]", Error)
		os.Exit(1)
	}
```
```
cmd\GitHubReleasesAssets\json.go:41:3: exitAfterDefer: os.Exit will exit, and `defer Response.Body.Close()` will not run (gocritic)
                os.Exit(1)
                ^
```
If snippet is not enough, source can be found [here](https://github.com/wipe2238/GitHubReleasesAssets/blob/0622654bf631128b994d76824336d164a27400bb/cmd/GitHubReleasesAssets/json.go#L36-L42)
