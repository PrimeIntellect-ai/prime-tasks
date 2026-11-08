Zero length encoding is considered invalid.
### GitHub repository with your minimal reproducible example (do not leave this field blank or fill out this field with "github.com/bufbuild/buf" or we will automatically close your issue, see the instructions above!)

https://github.com/daniel-wong-dfinity-org/foo.proto

### Commands

```shell
# I assume that buf 1.50.0 is installed and on your PATH.

echo -n '' | \
buf convert \
  foo.proto \
  --type=M \
  --from=-#format=binpb \
  --to=-#format=txtpb
```

### Output

```shell
Failure: --from: length of data read from "-#format=binpb" was zero
```

### Expected Output

None. Not even a trailing newline. Literally zero bytes.

### Anything else?

`buf convert` itself is able to produce 0 length encoded message in binpb format. Therefore, according to the tool itself, 0 length encoding is valid. For example:

```
$ echo '' | \
buf convert \
  foo.proto \
  --type=M \
  --from=-#format=txtpb \
  --to=-#format=binpb | \
wc
      0       0       0
```

### Additional contract requirements

- Empty input in `binpb`, `txtpb`, and `yaml` format represents an empty protobuf message and must be accepted by `buf convert`.
- Converting empty `binpb` input to `txtpb` must succeed and write zero bytes.
- Converting an empty protobuf message to `binpb` must write zero bytes.
- Empty input in `json` format must fail, and stderr must contain `Failure: --from:`, `json unmarshal:`, `proto:`, and `syntax error (line 1:1): unexpected token`.
