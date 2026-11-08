[BUG] - NewAtTimes Function Modifies Original Slice
### Describe the bug

In my attempts to parse a gocron.AtTimes back to a time.Time I discovered a strange behavior.
My current attempts consists of this part of the function, that takes the gocron.AtTimes and converts it back formated time Strings:
```go
func reverseParseTimes(atTimes gocron.AtTimes) []string {
	var times []string
	unparsedTimesSlice := atTimes()
	for _, atTime := range unparsedTimesSlice {
		location, _ := time.LoadLocation("Local")
		timeStr := gocron.TimeFromAtTime(atTime, location).Format("15:04")
		times = append(times, timeStr)
	}
	return times
}
```

When I execute this function multiple times with the same input atTimes then the atTimes seems to be modified and appended by the first entry each time.
These are the logger prints after each execution:
```bash
{"level":"info","msg":"Times: [0x863200 0x863200 0x863200]","time":"2024-12-18T10:13:51+01:00"}
{"level":"info","msg":"Parsed times: [09:59 09:30 09:30 09:30]","time":"2024-12-18T10:13:51+01:00"}
{"level":"info","msg":"Times: [0x863200 0x863200 0x863200 0x863200 0x863200]","time":"2024-12-18T10:13:54+01:00"}
{"level":"info","msg":"Parsed times: [09:59 09:30 09:30 09:30 09:30 09:30]","time":"2024-12-18T10:13:54+01:00"}
{"level":"info","msg":"Times: [0x863200 0x863200 0x863200 0x863200 0x863200 0x863200 0x863200]","time":"2024-12-18T10:14:05+01:00"}
{"level":"info","msg":"Parsed times: [09:59 09:30 09:30 09:30 09:30 09:30 09:30 09:30]","time":"2024-12-18T10:14:05+01:00"}
```
The original atTimes was only 9:30 and 9:59, therefore I expect only `[9:30 9:59]` as a return.

### To Reproduce

Steps to reproduce the behavior:

1. Create a `gocron.AtTimes` instance with two `AtTime` values, e.g., `9:30`and `9:59`.
2. Call the `reverseParseTimes` function with the created `gocron.AtTimes` instance.
3. Log the output of the `reverseParseTimes` function.
4. Repeat step 2 and 3 multiple times.

### Version
I used `v2.14.0`

### Expected behavior

I expect the `reverseParseTimes` function to consistently return the same parsed times without appending duplicate entries. Specifically, the expected output should be `[9:30 9:59]` for each execution.

### Additional context
I tried to look a bit into where the problem might be and discovered that changing the NewAtTimes function seems to fix my issue (although I am not sure if it creates other bugs, it was just a crude attempt).
Original `NewAtTimes` function:
```go
func NewAtTimes(atTime AtTime, atTimes ...AtTime) AtTimes {
    return func() []AtTime {
        atTimes = append(atTimes, atTime)
        return atTimes
    }
}
```
Modified `NewAtTimes` function:
[HIDDEN]

This was a fix proposed by Copilot so I would not trust it completely and I am not entirely sure what is different in the modified function.
[HIDDEN] [HIDDEN]

I observe the expected behavior with the modified `NewAtTimes` function:
```go
{"level":"info","msg":"Times: [0x863220 0x863220]","time":"2024-12-18T10:14:34+01:00"}
{"level":"info","msg":"Parsed times: [09:30 09:59]","time":"2024-12-18T10:14:34+01:00"}
{"level":"info","msg":"Times: [0x863220 0x863220]","time":"2024-12-18T10:14:35+01:00"}
{"level":"info","msg":"Parsed times: [09:30 09:59]","time":"2024-12-18T10:14:35+01:00"}
{"level":"info","msg":"Times: [0x863220 0x863220]","time":"2024-12-18T10:14:36+01:00"}
{"level":"info","msg":"Parsed times: [09:30 09:59]","time":"2024-12-18T10:14:36+01:00"}
```

### Additional contract requirements

- Repeated calls to an `AtTimes` value created with `NewAtTimes` must return the same configured values in the same order, without accumulating duplicate entries.
