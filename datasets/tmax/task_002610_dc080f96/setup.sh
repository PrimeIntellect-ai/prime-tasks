#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang espeak-ng
    pip3 install pytest

    mkdir -p /app

    # Generate audio file
    espeak-ng -w /app/requirements.wav "Group the events into exactly fifteen minute buckets. The output must match this exact template for each bucket. Print the word Bucket, then a space, then the bucket start timestamp in RFC3339 format, then a comma and a space, then Net Revenue:, a space, and the amount formatted to exactly two decimal places."

    # Create oracle Go code
    cat << 'EOF' > /app/oracle.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"time"
)

type Event struct {
	Timestamp time.Time `json:"timestamp"`
	Type      string    `json:"type"`
	Amount    float64   `json:"amount"`
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	buckets := make(map[time.Time]float64)

	for scanner.Scan() {
		line := scanner.Bytes()
		var e Event
		if err := json.Unmarshal(line, &e); err != nil {
			continue
		}

		bucketStart := e.Timestamp.Truncate(15 * time.Minute)

		if e.Type == "sale" {
			buckets[bucketStart] += e.Amount
		} else if e.Type == "refund" {
			buckets[bucketStart] -= e.Amount
		}
	}

	var times []time.Time
	for t := range buckets {
		times = append(times, t)
	}
	sort.Slice(times, func(i, j int) bool {
		return times[i].Before(times[j])
	})

	for _, t := range times {
		fmt.Printf("Bucket %s, Net Revenue: %.2f\n", t.Format(time.RFC3339), buckets[t])
	}
}
EOF

    # Compile oracle
    cd /app
    go build -o oracle_processor oracle.go
    rm oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
