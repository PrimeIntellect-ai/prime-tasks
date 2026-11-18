#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go binutils
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor/github.com/acmecorp/logsync
    mkdir -p /home/user

    # Create vendored go.mod
    cat << 'EOF' > /app/vendor/github.com/acmecorp/logsync/go.mod
module github.com/acmecorp/logsync

go 1.20
EOF

    # Create broken sync.go
    cat << 'EOF' > /app/vendor/github.com/acmecorp/logsync/sync.go
package logsync

// AdjustTimestamp applies the drift factor to the raw timestamp
func AdjustTimestamp(raw int64, drift float64) int64 {
    // BUG: Deliberately broken formula
    return raw + int64(drift * 1000)
}
EOF

    # Create oracle source code
    cat << 'EOF' > /tmp/oracle.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

type LogEntry struct {
	OriginalID int
	Timestamp  int64
	ServiceID  string
	Message    string
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var entries []LogEntry
	id := 0

	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, "|")
		if len(parts) != 4 {
			continue
		}
		serviceID := parts[0]
		rawStr := parts[1]
		driftStr := parts[2]
		message := parts[3]

		raw, err := strconv.ParseInt(rawStr, 10, 64)
		if err != nil || raw <= 0 {
			continue
		}

		drift, err := strconv.ParseFloat(driftStr, 64)
		if err != nil || drift < -0.5 || drift > 0.5 {
			continue
		}

		adjusted := raw + int64(float64(raw)*drift)
		entries = append(entries, LogEntry{
			OriginalID: id,
			Timestamp:  adjusted,
			ServiceID:  serviceID,
			Message:    message,
		})
		id++
	}

	sort.SliceStable(entries, func(i, j int) bool {
		if entries[i].Timestamp != entries[j].Timestamp {
			return entries[i].Timestamp < entries[j].Timestamp
		}
		if entries[i].ServiceID != entries[j].ServiceID {
			return entries[i].ServiceID < entries[j].ServiceID
		}
		return entries[i].OriginalID < entries[j].OriginalID
	})

	for _, e := range entries {
		fmt.Printf("[%d] %s: %s\n", e.Timestamp, e.ServiceID, e.Message)
	}
}
EOF

    # Compile the oracle
    cd /tmp
    go build -o /app/oracle_reconstructor oracle.go
    strip /app/oracle_reconstructor
    rm /tmp/oracle.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
