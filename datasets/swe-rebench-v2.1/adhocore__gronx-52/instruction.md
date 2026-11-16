Unexpected "unreachable year segment: 2024" error for valid cron expression in PrevTickBefore
**Issue Summary:**
When using the `PrevTickBefore` function with a specific cron expression and a reference time within the same year, the function unexpectedly returns an "unreachable year segment" error. This occurs even when the year in the cron expression matches the reference time year.

**Expected Behavior:**
Given the cron expression `"30 15 4 11 * 2024"`, which schedules a job for **November 4, 2024, at 15:30**, and a reference time of **November 8, 2024, at 22:18:16 UTC**, calling `PrevTickBefore` should return the previous tick of **November 4, 2024, at 15:30:00 UTC** without any errors.

**Actual Behavior:**
The function returns an error indicating `"unreachable year segment: 2024"`.

**Test Case:**
Here is a minimal test case that reproduces the issue:

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

	// Cron expression for 15:30 on November 4, 2024
	cronExpr := "30 15 4 11 * 2024"

	// Expected outcome: November 4, 2024, at 15:30
	expectedTime := time.Date(2024, time.November, 4, 15, 30, 0, 0, time.UTC)

	// Call PrevTickBefore
	actualTime, err := gronx.PrevTickBefore(cronExpr, now, true)

	// Simplified check for error and time
	if err != nil {
		fmt.Printf("Test FAILED: Did not expect an error, but got: %s\n", err)
	} else if !actualTime.Equal(expectedTime) {
		fmt.Printf("Test FAILED: Expected previous tick to be %v, but got %v.\n", expectedTime, actualTime)
	} else {
		fmt.Println("Test PASSED: Year segment 2024 is reachable, and PrevTickBefore returned the correct previous tick.")
	}
}

func main() {
	TestIsUnreachableYear_CurrentYear()
}
```

**Steps to Reproduce:**
1. Use the above test case, which calls `PrevTickBefore` with a reference time (`now`) in November 2024 and a cron expression for **November 4, 2024, at 15:30**.
2. Observe that the function returns an "unreachable year segment" error instead of providing the expected previous tick time.
