#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip git golang-go
    pip3 install pytest

    # Create oracle program
    mkdir -p /opt/oracle/src
    cat << 'EOF' > /opt/oracle/src/main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"time"
)

type LogEntry struct {
	Time   string `json:"time"`
	Stream string `json:"stream"`
	Log    string `json:"log"`
	Parsed time.Time `json:"-"`
	Raw    string `json:"-"`
}

func parseTime(tStr string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339Nano, tStr)
	if err != nil {
		return time.Parse(time.RFC3339, tStr)
	}
	return t, nil
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var entries []LogEntry
	for scanner.Scan() {
		line := scanner.Text()
		var entry LogEntry
		if err := json.Unmarshal([]byte(line), &entry); err == nil {
			t, err := parseTime(entry.Time)
			if err == nil {
				entry.Parsed = t
				entry.Raw = line
				entries = append(entries, entry)
			}
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		return entries[i].Parsed.Before(entries[j].Parsed)
	})
	for _, e := range entries {
		fmt.Println(e.Raw)
	}
}
EOF
    cd /opt/oracle/src
    go mod init oracle
    go build -o /opt/oracle/log-stitcher-oracle main.go

    # Setup the agent's repository
    mkdir -p /app/log-stitcher
    cd /app/log-stitcher
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    cat << 'EOF' > main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"time"
)

type LogEntry struct {
	Time   string `json:"time"`
	Stream string `json:"stream"`
	Log    string `json:"log"`
	Parsed time.Time `json:"-"`
	Raw    string `json:"-"`
}

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var entries []LogEntry
	for scanner.Scan() {
		line := scanner.Text()
		var entry LogEntry
		if err := json.Unmarshal([]byte(line), &entry); err == nil {
			t, err := parseTime(entry.Time)
			if err == nil {
				entry.Parsed = t
				entry.Raw = line
				entries = append(entries, entry)
			}
		}
	}
	sort.SliceStable(entries, func(i, j int) bool {
		return entries[i].Parsed.Before(entries[j].Parsed)
	})
	for _, e := range entries {
		fmt.Println(e.Raw)
	}
}
EOF

    cat << 'EOF' > parser.go
package main

import (
	"time"
)

func parseTime(tStr string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339Nano, tStr)
	if err != nil {
		return time.Parse(time.RFC3339, tStr)
	}
	return t, nil
}
EOF

    go mod init log-stitcher
    mkdir vendor
    git add main.go parser.go go.mod vendor
    git commit -m "Initial commit"
    git tag v1.1.0

    # Add a dummy commit
    echo "// dummy" >> main.go
    git add main.go
    git commit -m "Minor cleanup"

    # Introduce the bug
    cat << 'EOF' > parser.go
package main

import (
	"time"
)

func parseTime(tStr string) (time.Time, error) {
	return time.Parse(time.RFC3339Nano, tStr)
}
EOF
    git add parser.go
    git commit -m "Optimize timestamp parsing"

    # Add another dummy commit
    echo "// another dummy" >> main.go
    git add main.go
    git commit -m "Update main.go comments"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/log-stitcher
