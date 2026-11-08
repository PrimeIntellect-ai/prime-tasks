bug: Decoder returns no error on short read
### What version of fxamacker/cbor are you using?
	github.com/fxamacker/cbor/v2 v2.4.0


### Does this issue reproduce with the latest release?
  yes

### What OS and CPU architecture are you using (`go env`)?
GOARCH="amd64"
GOHOSTOS="linux"

<details><summary><code>go env</code> Output</summary><br><pre>
$ go env

</pre></details>

### What did you do?
I'm making a stream transport that chunks data into frames and provides  io.Reader and io.Writer interfaces.
the Read() implementation is nonblocking and returns 0, nil if no data is yet buffered, but no end-of-stream protocol message has arrived, so io.EOF is *not* returned until the remote peer has sent an end-of-stream message.

<!--
If possible, provide steps and/or code to reproduce the problem.
-->

here is a link to my code and test:
https://github.com/katzenpost/katzenpost/blob/c676eaa9fd1fb5c2db1bd30106b4c97bab79a47c/stream/stream_test.go#L269



### What did you expect to see?
I expected decoder.Decode(fooType) to return an error or correctly read data until a fooType was decoded

### What did you see instead?
no error was returned and fooType was left uninitialized

### Additional contract requirements

- A Read that returns (0, nil) (zero bytes read with a nil error) must not by itself cause Decode or Skip to return an error. Decode and Skip must continue reading until a complete CBOR data item is available or the underlying io.Reader returns a non-nil error. Consequently, a Reader that alternates between (0, nil) and normal reads must still allow Decode and Skip to succeed.
