klogr: Don't print level=n in a log line
/kind bug

**What steps did you take and what happened:**
When printing logs I see a lot of `level="0"` or `level="1"` etc.

There is no reason to print this information and only adds to the difficulty of reading lines. If anything the level could be similar to the `I` or `E` that starts an `Info` or `Error` Log, but it does not need a whole field.

**Anything else you would like to add:**

[HIDDEN]

https://github.com/kubernetes/klog/blob/master/klogr/klogr.go#L143-L148

edit: "no reason" is too strong. There may be a use case for leaving this in, but I can't think of it beyond some other system parsing logs and wanting to only see specific log lines. Or perhaps logging -vMAX and then filtering on your logging backend.

### Additional contract requirements

- Enabled `klogr.Info` output must not include a synthetic numeric `level` field, regardless of the configured verbosity level.
