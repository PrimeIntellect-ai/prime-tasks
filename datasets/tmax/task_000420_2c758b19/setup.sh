#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git
    pip3 install pytest

    # Create directories
    mkdir -p /app/corpora/clean /app/corpora/evil
    mkdir -p /home/user/diag_service

    # Build the diag_oracle binary
    cat << 'EOF' > /app/oracle.go
package main

import (
	"encoding/json"
	"fmt"
	"os"
)

type Payload struct {
	UnixTs        int64  `json:"unix_ts"`
	TzOffsetHours int    `json:"tz_offset_hours"`
	Data          string `json:"data"`
	Checksum      string `json:"checksum"`
}

func main() {
	if len(os.Args) < 2 {
		os.Exit(1)
	}
	b, err := os.ReadFile(os.Args[1])
	if err != nil {
		os.Exit(1)
	}
	var p Payload
	if err := json.Unmarshal(b, &p); err != nil {
		os.Exit(1)
	}

	// Check modulo rule
	if (p.UnixTs/3600 + int64(p.TzOffsetHours)) % 24 != 0 {
		os.Exit(1)
	}

	// Check checksum
	var c byte
	for i := 0; i < len(p.Data); i++ {
		c ^= p.Data[i]
	}
	if fmt.Sprintf("%02x", c) != p.Checksum {
		os.Exit(1)
	}

	os.Exit(0)
}
EOF
    cd /app
    go build -ldflags="-s -w" -o diag_oracle oracle.go
    rm oracle.go

    # Generate corpora using Python
    cat << 'EOF' > /app/gen_corpora.py
import json
import os

def gen(ts, tz, data, out, bad_checksum=False):
    c = 0
    for char in data:
        c ^= ord(char)
    if bad_checksum:
        c = (c + 1) % 256
    with open(out, 'w') as f:
        json.dump({"unix_ts": ts, "tz_offset_hours": tz, "data": data, "checksum": f"{c:02x}"}, f)

gen(3600, 23, "hello", "/app/corpora/clean/1.json")
gen(7200, 22, "world", "/app/corpora/clean/2.json")

# Evil - bad modulo
gen(3600, 22, "hello", "/app/corpora/evil/1.json")
# Evil - bad checksum
gen(3600, 23, "hello", "/app/corpora/evil/2.json", bad_checksum=True)
EOF
    python3 /app/gen_corpora.py
    rm /app/gen_corpora.py

    # Setup git repository
    cd /home/user/diag_service
    git init
    git config user.email "test@example.com"
    git config user.name "Test User"

    cat << 'EOF' > diag.go
package diag
import "time"
func GetOffset(ts time.Time, utc time.Time) int {
	return ts.Hour() - utc.Hour()
}
EOF
    cat << 'EOF' > diag_test.go
package diag
import (
	"testing"
	"time"
)
func TestGetOffset(t *testing.T) {
	utc := time.Date(2023, 1, 1, 12, 0, 0, 0, time.UTC)
	ts := time.Date(2023, 1, 1, 15, 0, 0, 0, time.FixedZone("UTC+3", 3*3600))
	if GetOffset(ts, utc) != 3 {
		t.Fatalf("expected 3")
	}
}
EOF
    go mod init diag
    git add .
    git commit -m "Initial commit"
    git tag v1.0.0

    # Introduce bug
    cat << 'EOF' > diag.go
package diag
import "time"
func GetOffset(ts time.Time, utc time.Time) int {
	return utc.Hour() - ts.Hour()
}
EOF
    git add diag.go
    git commit -m "Update offset calculation"

    # Create user and fix permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
