[HIDDEN]
**Describe the bug**

In the code below the "name=" string is a cutset (a set of characters) to be removed, and not a prefix.
https://github.com/mgechev/revive/blob/b03e54f617491984b41f0411b69326f94d03a76f/rule/struct-tag.go#L139-L140

`getTagName` function will return `o` instead of `ameno` for the this struct tag: `protobuf:"varint,name=ameno"`.

### Additional contract requirements

- For protobuf tags, derive the tag name from the value following `name=` without stripping valid leading characters. The value `name=ameno` must be recognized as `ameno`.
