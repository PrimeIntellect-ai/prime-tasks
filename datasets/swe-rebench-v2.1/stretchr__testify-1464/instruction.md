Same time values in same timezone are not equal
https://go.dev/play/p/hHHtLV8pnt0?v=goprev

```go
func TestAAAA(t *testing.T) {
	t1 := time.Now()
	// Create a copy of the same time using the same local timezone.
	t2 := t1.In(time.Local)
	assert.Equal(t, t1, t2)
}
```
```bash
=== RUN   TestAAAA
    prog_test.go:16:
        	Error Trace:	/tmp/sandbox2123072853/prog_test.go:16
        	Error:      	Not equal:
        	            	expected: time.Date(2009, time.November, 10, 23, 0, 0, 0, time.Local)
        	            	actual  : time.Date(2009, time.November, 10, 23, 0, 0, 0, time.Local)

        	            	Diff:
        	            	--- Expected
        	            	+++ Actual
        	            	@@ -1,2 +1,2 @@
        	            	-(time.Time) 2009-11-10 23:00:00 +0000 UTC m=+0.000000001
        	            	+(time.Time) 2009-11-10 23:00:00 +0000 UTC

        	Test:       	TestAAAA
```

In addition to this, I think it would be good if same time instants with **different** timezones would be equal. In my use case, it would help if time was compared using [time.Equal](https://pkg.go.dev/time#Time.Equal).
