Allow new-line and indented map as value of slice
I want to decode new-line and indented map as value of slice.

like follows

```yaml
a:
-
  b: d
  c: e
-
  b: f
  c: g
```

| | go-yaml/yaml | goccy/go-yaml v1.4.1 |
| --- | --- | --- |
| decode | can decode | error |
| play.golang.org | [here](https://play.golang.org/p/Niu8FXan10A) | [here](https://play.golang.org/p/6G8ZrkdsoXb) |

I have tried this problem but have not solved it yet ... so I first register this issue.

### Additional contract requirements

Decoding the example above must succeed. The value of `a` must be a slice
containing one map per `-` sequence entry, where each map holds the
newline-separated, indented key/value pairs that follow that entry. For the
example, the decoded value is equivalent to:

```go
map[string][]map[string]string{
    "a": {
        {"b": "d", "c": "e"},
        {"b": "f", "c": "g"},
    },
}
```


- For the parser input with sequence entries `b: c` / `d: e` and `f: g` / `h: i`, the normalized output must be:

```yaml
a:
- b: c
  d: e
- f: g
  h: i
```
