How to solve precision problem in tengo?
Hi,  thanks for such a great project!

How to solve precision problem in tengo?
```go
json := import("json")
fmt := import("fmt")


base_info := bytes(`{
        "1":7075984636689534001,
        "2":7075984636689534002
}`)
m := json.decode(base_info)
fmt.println(m[1])
```

result: 7075984636689534000
