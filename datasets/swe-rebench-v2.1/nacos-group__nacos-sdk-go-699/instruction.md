[version compatibility] success field of nacos server's response is empty
### What version of nacos-sdk-go are you using?
v2.2.2

### What version of nacos-sever are you using?
2.0.3

### What version of Go are you using (`go version`)?
go version go1.21.5 darwin/arm64

### What operating system (Linux, Windows, …) and version?

### What did you do?
If possible, provide a recipe for reproducing the error.
![image](https://github.com/nacos-group/nacos-sdk-go/assets/38815080/02c178c5-0465-4251-8c7a-0e6ce8585a17)


As you can see, there is no `field` for `success` in `response`, resulting in `unmarshal` to `success` in response being set to `false`. However, `resultCode` is 200, which means that the result of the request is successful.

-------

可以看到，`response`中没有`success`这个`field`，导致`unmarshal`到response中的`success`被设置成`false`。但是`resultCode`为`200`，表示这个请求的结果是成功的。

### What did you expect to see?

### What did you see instead?

### Additional contract requirements

- If an RPC response omits `success` and has `resultCode` 200, it must be reported as successful.
