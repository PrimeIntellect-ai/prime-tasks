svg can't get the correct clip-path if url contains ')' or '('
et: <path clip-path="url(https://xxx.com?keyword=(1)#mask-145)

### Additional contract requirements

- `urlIdRef(id)` must return references in the form `url("<URL>#<id>")`, using the current window location with any existing fragment removed and replacing `"` in the URL with `%22`. For example, it must return `url("https://test.com/#123-blah")` for `urlIdRef('123-blah')` at `https://test.com`, and `url("https://test.com/path#123-blah")` at `https://test.com/path#existing-hash`.
