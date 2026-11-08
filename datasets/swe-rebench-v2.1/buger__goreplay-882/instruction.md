validate response without Reason Phrase
With version master, headers are missing for response without Reason Phrase in HTTP Status (similar than #868)

Exemple :
```
HTTP/1.1 200
X-Content-Type-Options: nosniff
Content-Type: application/json;charset=UTF-8

1479
{
.............<json content>..........
}
```

Explanation : [HIDDEN]
github.com/buger/goreplay/proto.HasResponseTitle at proto.go:371
github.com/buger/goreplay/proto.HasTitle at proto.go:416
github.com/buger/goreplay/proto.ParseHeaders at proto.go:117

### Additional contract requirements

- A valid HTTP response status line must be accepted both when a Reason-Phrase follows the three-digit status code and when the code is followed immediately by CRLF.
- Header parsing must preserve response headers in either form, including responses with a Reason-Phrase.
