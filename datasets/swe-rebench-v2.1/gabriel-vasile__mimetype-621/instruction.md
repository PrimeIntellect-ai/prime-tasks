pzstd file is not detected as zstd
**Attach the file for which the detection is inaccurate**
[test.zip](https://github.com/user-attachments/files/18141160/test.zip)
test.txt.zst uses zstd
test2.txt.zst uses pzstd

**Expected MIME type**
`application/zstd`

**Returned MIME type**
`application/octet-stream`

**Version of the library you are using**
`v1.4.7`

**Output of `go version`**
`go version go1.23.4 linux/amd64`

**Additional context**
https://github.com/facebook/zstd
Files created using pzstd are not detection correctly, if use `file` command both will be detected as `application/zstd`

### Additional contract requirements

- The four-byte signature `\x50\x2A\x4D\x18` must be detected as `application/zstd`.
