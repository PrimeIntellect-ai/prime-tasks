Response headers defined in embedded struct are ignored
**Describe the bug**

When `Test` [response header](https://github.com/swaggest/rest#response-encoder) is defined using embedded struct like this

```
type MyEmbedded struct {
    Test string          `header:"Test" json:"-"`
}

type MyResponse struct {
    MyEmbedded
    Other string          `json:"other"`
}
```
such header is not present in API response. No such problem when header is defined directly i.e.
```
type MyResponse struct {
    Test string          `header:"Test" json:"-"`
    Other string          `json:"other"`
}
```

**Expected behavior**
Response header defined using embedded struct should be present in response.
