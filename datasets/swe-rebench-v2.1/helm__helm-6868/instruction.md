Feature request: a `helm version` option that works consistently across v2 and v3
I am consuming Helm programmatically and sometimes need to issue slightly different command syntax according to whether the user has Helm 2 or Helm 3.  I can try to detect this using `helm version` _but_...

* On Helm 2, `helm version` attempts to reach Tiller, which is potentially slow.  I can avoid this with `helm version -c` but...
* On Helm 3, `helm version -c` is an error.
* On Helm 2, `helm version --short` returns a string of the form `Client: v2.14.3+g0e7f3b6` (plus server info which can be suppress with `-c`)
* On Helm 3, `helm version --short` returns a string of the form `v3.0.0-beta.2+g26c7338` (no `Client: ` prefix)

All this makes detecting v2 vs v3 a bit fiddly.  I could issue `helm version -c` and assume v3 if I get an error, but perhaps it would be nice to continue to support `-c` as a hidden flag and have it force the output to the same format as v2?

### Additional contract requirements

The compatibility behavior of `-c` is to print Helm's client version information without requiring server-version information. This does not require a Helm 2-specific prefix or serialized representation. The shorthand must be accepted but must not be advertised in version help.
