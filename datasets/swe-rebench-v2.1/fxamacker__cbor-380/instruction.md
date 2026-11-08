bug: Unmarshal and Valid should check following extraneous data
### What version of fxamacker/cbor are you using?
v2.4.0

### Does this issue reproduce with the latest release?
Yes

### What OS and CPU architecture are you using (`go env`)?
MacOS, m1
<details><summary><code>go env</code> Output</summary><br><pre>
$ go env

</pre></details>

### What did you do?

```go
data := []byte{0, 1, 2, 3}
err := cbor.Valid(data) // should return a error

var val interface{}
err = cbor.Unmarshal(data, &val) // should return a error
```

<!--
If possible, provide steps and/or code to reproduce the problem.
-->



### What did you expect to see?



### What did you see instead?
