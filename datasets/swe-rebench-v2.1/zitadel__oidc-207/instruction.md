`invalid memory address or nil pointer dereference` when accessing UserInfoAddress
**Describe the bug**
When user info is missing address field it's decoded into `userinfo` struct where `Address` field has `UserInfoAddress` type but `nil` value.

`UserInfoAddress` type doesn't expect `nil` as receiver, so code like `info.GetAddress().GetCountry()` panics.

**To Reproduce**
Steps to reproduce the behavior:
1. Unmarshal userinfo without address
2. Try `info.GetAddress().GetCountry()`
3. See panic

**Expected behavior**
Probably, returning default values for all fields (e.g. `""`).

Another (IMO better but breaking) way is to return a pointer. So it will be possible to check value `GetAddress() == nil`

**Additional context**
Temp workaround:
```go
func isNil(val any) bool {
	return val == nil || (reflect.ValueOf(val).Kind() == reflect.Ptr && reflect.ValueOf(val).IsNil())
}

addr := info.GetAddress()
if !isNil(addr) {
  // ...
}
```

### Additional contract requirements

When the address is absent or null, accessing it through userinfo must not cause the nil-dereference described above. It is acceptable either for GetAddress to return a nil value that callers can check before using it, or for it to return an address value whose getters safely return defaults for missing fields.
