#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang time
    pip3 install pytest pandas

    mkdir -p /app
    mkdir -p /home/user

    # Create the oracle Go code
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"sort"
	"time"
)

type LogEntry struct {
	Timestamp      string `json:"timestamp"`
	IP             string `json:"ip"`
	ResponseTimeMs int    `json:"response_time_ms"`
	Endpoint       string `json:"endpoint"`
	Status         int    `json:"status"`
}

type GroupKey struct {
	Window   string
	Endpoint string
}

type GroupData struct {
	ResponseTimes []int
	ErrorCount    int
}

func main() {
	if len(os.Args) < 3 {
		return
	}
	inFile := os.Args[1]
	outFile := os.Args[2]

	f, err := os.Open(inFile)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	groups := make(map[GroupKey]*GroupData)

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		time.Sleep(1 * time.Microsecond)
		var entry LogEntry
		if err := json.Unmarshal(scanner.Bytes(), &entry); err != nil {
			continue
		}

		t, err := time.Parse(time.RFC3339, entry.Timestamp)
		if err != nil {
			continue
		}

		window := t.Truncate(5 * time.Minute).Format(time.RFC3339)
		key := GroupKey{Window: window, Endpoint: entry.Endpoint}

		if _, ok := groups[key]; !ok {
			groups[key] = &GroupData{}
		}
		groups[key].ResponseTimes = append(groups[key].ResponseTimes, entry.ResponseTimeMs)
		if entry.Status >= 400 {
			groups[key].ErrorCount++
		}
	}

	var keys []GroupKey
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool {
		if keys[i].Window == keys[j].Window {
			return keys[i].Endpoint < keys[j].Endpoint
		}
		return keys[i].Window < keys[j].Window
	})

	out, err := os.Create(outFile)
	if err != nil {
		panic(err)
	}
	defer out.Close()

	fmt.Fprintln(out, "window_start,endpoint,p95_response_time,error_count")
	for _, k := range keys {
		data := groups[k]
		sort.Ints(data.ResponseTimes)
		idx := int(math.Ceil(float64(len(data.ResponseTimes))*0.95)) - 1
		if idx < 0 {
			idx = 0
		}
		fmt.Fprintf(out, "%s,%s,%d,%d\n", k.Window, k.Endpoint, data.ResponseTimes[idx], data.ErrorCount)
	}
}
EOF

    # Build and strip the oracle
    cd /tmp
    go build -ldflags="-s -w" -o /app/bucket_oracle oracle.go
    chmod +x /app/bucket_oracle

    # Generate test log file
    cat << 'EOF' > /tmp/generate_logs.py
import json
import random
from datetime import datetime, timedelta

endpoints = ["/api/v1/users", "/api/v1/orders", "/api/v1/products", "/login", "/checkout"]
start_time = datetime(2023, 10, 1, 12, 0, 0)

with open("/home/user/requests.log", "w") as f:
    for i in range(1000000):
        t = start_time + timedelta(seconds=random.randint(0, 7200))
        entry = {
            "timestamp": t.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "ip": f"192.168.1.{random.randint(1, 255)}",
            "response_time_ms": random.randint(10, 1000),
            "endpoint": random.choice(endpoints),
            "status": random.choice([200, 200, 200, 201, 400, 404, 500])
        }
        f.write(json.dumps(entry) + "\n")
EOF
    python3 /tmp/generate_logs.py
    rm /tmp/generate_logs.py /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
