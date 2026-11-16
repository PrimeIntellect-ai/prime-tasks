Regex Built In should avoid MustCompile to avoid potential panic
https://github.com/skx/monkey/blob/master/evaluator/stdlib_core.go#L174C59-L175C2

[HIDDEN] Potentially even caching the regex compiled.


```go
var regexCacheLock sync.Mutex
var regexCache = map[string]*regexp.Regexp{}

func compileRegex(reg string) (*regexp.Regexp, error) {
    regexCacheLock.Lock()
    defer regexCacheLock.Unlock()

    reg, ok := regexCache[reg]
    if !ok {
        reg, err = regexp.MustCompile(reg)
        if err != nil {
            return nil, err
        }
        regexCache[reg] = reg
    }

    return reg, nil
}

...

// regular expression match
func matchFun(args ...object.Object) object.Object {

    [HIDDEN]
    [HIDDEN]
    [HIDDEN]
    if err != nil {
        return newError("failed to compile regex: %v", err)
    }
```

### Additional contract requirements

- Regex matching through the built-in and the `~=` operator must return an evaluator error for an invalid pattern rather than panic.
