Client is leaking TCP connections
I discovered this issue with the grafana flux datasource, but traced it back to the client. It seems TCP connections are not closed after calling `client.Close()`.

Output of the program below:
```
...
Query returned 181 rows
Open TCP connections:       59
Query returned 181 rows
Open TCP connections:       60
Query returned 181 rows
Open TCP connections:       61
Query returned 181 rows
Open TCP connections:       62
...
```

Please run this go program to see for yourself (when on linux, change .8086 to :8086 for the netstat command).
```go
package main

import (
	"context"
	"fmt"
	"log"
	"os/exec"

	influxdb2 "github.com/influxdata/influxdb-client-go"
)

func main() {
	for {
		client := influxdb2.NewClient("https://demo.factry.io:8086", "flux:xulf")
		queryAPI := client.QueryAPI("factry")

		query := `from(bucket: "simulation_tanksystem")
							|> range(start: -2h, stop:-30m)
							|> filter(fn: (r) => r._measurement == "WP1_fill_level")
							|> aggregateWindow(every: 30s, timeSrc: "_start", fn: mean, createEmpty:false)`

		// get parser flux query result
		result, err := queryAPI.Query(context.Background(), query)
		if err != nil {
			fmt.Println(err)
			return
		}
	        defer result.Close()

		count := 0
		// Use Next() to iterate over query result lines
		for result.Next() {
			// Observe when there is new grouping key producing new table
			count++
		}
		fmt.Printf("Query returned %v rows\n", count)
		if result.Err() != nil {
			fmt.Printf("Query error: %s\n", result.Err().Error())
		}

		// Ensures background processes finishes
		client.Close()

		getOpenConns()
	}
}

func getOpenConns() {
	out, err := exec.Command("sh", "-c", `netstat -atn | grep ".8086" | wc -l`).Output()
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Open TCP connections: %s", out)
}

```

### Additional contract requirements

When a client uses an HTTP client it created itself, calling `Client.Close()` must close that HTTP client's idle connections. This allows repeated client creation and closure without leaving idle TCP connections open.
