`NextTickAfter` returning "unreachable year segment" error when `inclRefTime` is `false`
Thank you very much for the previous fix in #51.
I have encountered another test case on `v1.19.4` that seems problematic.

### Description

When I use `NextTickAfter` with `inclRefTime` set to `false`, I encounter an "unreachable year segment: 2024" error, even though the next valid occurrence within the year 2024 should still be reachable. This happens when checking for the next tick of `"30 15 31 12 * 2024"` as of November 8, 2024, at 22:18:16 UTC. I would expect this call to return December 31, 2024, at 15:30, but instead, it throws an error.

### Test Case to Reproduce

Here is a minimal test case to reproduce the issue:

```go
package main

import (
	"fmt"
	"time"

	"github.com/adhocore/gronx"
)

func TestIsUnreachableYear_CurrentYear() {
	// Set reference time ("now") to November 8, 2024, at 22:18:16 UTC
	now := time.Date(2024, time.November, 8, 22, 18, 16, 0, time.UTC)

	// Cron expression for 15:30 on December 31, 2024
	cronExpr := "30 15 31 12 * 2024"

	// Expected outcome: December 31, 2024, at 15:30
	expectedTime := time.Date(2024, time.December, 31, 15, 30, 0, 0, time.UTC)

	// Call NextTickAfter with inclRefTime set to false
	actualTime, err := gronx.NextTickAfter(cronExpr, now, false)

	// Simplified check for error and time
	if err != nil {
		fmt.Printf("Test FAILED: Did not expect an error, but got: %s\n", err)
	} else if !actualTime.Equal(expectedTime) {
		fmt.Printf("Test FAILED: Expected next tick to be %v, but got %v.\n", expectedTime, actualTime)
	} else {
		fmt.Println("Test PASSED: Year segment 2024 is reachable, and NextTickAfter returned the correct next tick.")
	}
}

func main() {
	TestIsUnreachableYear_CurrentYear()
}
```

### Expected Behavior
With `inclRefTime` set to `false`, the next tick after November 8, 2024, at 22:18:16 UTC for `"30 15 31 12 * 2024"` should still be December 31, 2024, at 15:30. The `inclRefTime` parameter should not affect the year reachability in this case.

### Observed Behavior
The `NextTickAfter` function returns an error: `unreachable year segment: 2024`

This error occurs only when `inclRefTime` is set to `false`, and it seems like a bug because the next valid time within 2024 should still be reachable.

Thank you for looking into this! Please let me know if additional details are needed.
