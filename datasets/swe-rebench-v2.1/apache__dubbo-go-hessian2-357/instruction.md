两个Map结构不同但值为nil时，decode  will panic
<!-- Please use this template while reporting a bug and provide as much info as possible. Not doing so may result in your bug not being addressed in a timely manner. Thanks!

-->


**What happened**:
两个Map结构不同但值为nil时，decode  will panic
**What you expected to happen**:
返回空Map
**How to reproduce it (as minimally and precisely as possible)**:
```
type UserInfo struct {
	Name    string
	Address map[string]string
	Family  map[string]int
}

func (UserInfo) JavaClassName() string {
	return "com.test.ReqInfo"
}

func TestIssueCase(t *testing.T) {
	req := &UserInfo{
		Name:    "test",
		Address: nil,
		Family:  nil,
	}

	hessian.RegisterPOJO(req)

	encoder := hessian.NewEncoder()
	err := encoder.Encode(req)
	if err != nil {
		t.Error(err)
		return
	}

	enBuf := encoder.Buffer()

	decoder := hessian.NewDecoder(enBuf)
	deReq, err := decoder.Decode()
	assert.Nil(t, err)

	t.Log(deReq)

	assert.True(t, reflect.DeepEqual(req, deReq))
}

```
```
=== RUN   TestIssueCase
--- FAIL: TestIssueCase (0.00s)
panic: reflect.Set: value of type map[string]string is not assignable to type map[string]int [recovered]
	panic: reflect.Set: value of type map[string]string is not assignable to type map[string]int
```
**Anything else we need to know?**:
