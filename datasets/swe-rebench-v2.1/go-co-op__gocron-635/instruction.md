v2 daily job seems to execute in an infinite loop
### Describe the bug

When starting the scheduler after adding a daily job it seems to execute in an infinite loop. A minimal reproduction of the issue is below. I could be "holding it wrong", so to speak too.

Prior to v2 I was using this a daily job like so:
```
_, err := scheduler.Every(1).Day().At("00:00").Do(func() {
	// Do the thing
})
```

After checking the [godocs for DailyJob](https://pkg.go.dev/github.com/go-co-op/gocron/v2#DailyJob), it looked like this would be the v2 equivalent:

```
_, err = scheduler.NewJob(
	gocron.DailyJob(1, gocron.NewAtTimes(
		gocron.NewAtTime(0, 0, 0),
	)),
	gocron.NewTask(func() {
		// Do the thing
	}),
)
```

### To Reproduce

I have a minimal reproduction of the issue.

`go.mod` entry:
`github.com/go-co-op/gocron/v2 v2.0.0`

Current hashes in `go.sum`:
```
github.com/go-co-op/gocron/v2 v2.0.0 h1:wVB5Bh+665+r/zQ+ErsyUypyPWGozEnNV7EEZ8D0HIU=
github.com/go-co-op/gocron/v2 v2.0.0/go.mod h1:DodDqurAedt8cj/dbFM8obVSgPv0Vch80eF7neNVwmg=
```

```go
package main

import (
	"fmt"
	"log"
	"time"

	"github.com/go-co-op/gocron/v2"
)

func main() {
	scheduler, err := gocron.NewScheduler()
	if err != nil {
		log.Fatalf("Failed to create scheduler: %s", err)
	}

	_, err = scheduler.NewJob(
		gocron.DailyJob(
			1,
			gocron.NewAtTimes(
				gocron.NewAtTime(0, 0, 0),
			),
		),
		gocron.NewTask(func() {
			fmt.Printf("Task ran!\n")
		}),
	)

	if err != nil {
		log.Fatalf("Failed to schedule job: %s", err)
	}

	scheduler.Start()

	time.Sleep(1 * time.Second)

	err = scheduler.StopJobs()
	if err != nil {
		log.Fatalf("Failed to stop jobs: %s", err)
	}
	err = scheduler.Shutdown()
	if err != nil {
		log.Fatalf("Failed to shutdown scheduler: %s", err)
	}
}
```

Running this results in about 45k "Task ran!" messages on my machine.

### Version

> The release version or commit SHA you're using.

v2.0.0

> Have you tried the latest version?

Yes

### Expected behavior

The daily job should execute daily.

### Additional context

N/A
