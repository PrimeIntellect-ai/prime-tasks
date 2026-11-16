Integer overflow in time.Time comparison
## Description
time.Time comparison rely on https://pkg.go.dev/time#Time.UnixNano, but documentation explicitly said, that it has undefined behavior is data is bigger than year 2262 (since it not fit in int64)

## Step To Reproduce
```go
func TestTime(t *testing.T) {
	require.Less(t, time.Now(), time.Date(2263, 0, 0, 0, 0, 0, 0, time.Local))
}
```
Error:      	"2024-03-29 08:20:14.8719425 +0300 MSK m=+0.001135586" is not less than "2262-11-30 00:00:00 +0300 MSK"
