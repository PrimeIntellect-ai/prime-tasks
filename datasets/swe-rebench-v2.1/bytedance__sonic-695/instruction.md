There is an panic at github.com/bytedance/sonic/internal/decoder/errors.(*MismatchTypeError).Error
There is an nil pointer panic in my prod env.

`runtime error: invalid memory address or nil pointer dereference
`
```
github.com/bytedance/sonic/internal/decoder/errors.(*MismatchTypeError).Error(0x2ff8980?)
	:1 +0x25
```
The code just like:

```
var sonicConfig = sonic.Config{
	EscapeHTML: true,
}.Froze()

err:=sonicConfig.Unmarshal(data, v)
if err!=nil{
  print(err.Error())
}
```
It panic when i call `err.Error()`
