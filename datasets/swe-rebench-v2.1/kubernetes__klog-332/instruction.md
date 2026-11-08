`KVListFormat` shadow's the Key if It is not a valid string
/kind bug

**What steps did you take and what happened:**
While trying to take a stab at #275 I noticed that there is a lingering issue in the `KVListFormat` function in terms of how it processes the keys

https://github.com/kubernetes/klog/blob/9c48b7d0ba16c13eb24c2311f591a69175f5cb86/internal/serialize/keyvalues.go#L112-L118

In case if the `key` passed to the `KVListFormat` is not of string type, this ends up consuming the key and only printing the value.

**What did you expect to happen:**
Based on the current comment/code, the expectation is that it will log the struct using `fmt.Sprintf("%s", k)` however, this is not working [HIDDEN]

**Anything else you would like to add:**
NA

### Additional contract requirements

- For every non-string key passed to `KVListFormat`, include the key in the output rendered as `fmt.Sprintf("%s", key)`, along with its corresponding value; do not omit the key.
