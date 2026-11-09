#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go sqlite3 libsqlite3-dev bc
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/processor

    # Create SQLite DB
    sqlite3 /app/telemetry.db "CREATE TABLE events (id TEXT, peak_amplitude REAL);"
    sqlite3 /app/telemetry.db "INSERT INTO events (id, peak_amplitude) VALUES ('EVT-9942', 15042.1);"
    sqlite3 /app/telemetry.db "INSERT INTO events (id, peak_amplitude) VALUES ('EVT-1111', 10000.0);"

    # Create dummy WAV file (100KB to make 1-byte read slow)
    dd if=/dev/urandom of=/app/telemetry.wav bs=1024 count=100

    # Create buggy Go code
    cat << 'EOF' > /app/processor/main.go
package main

import (
	"database/sql"
	"fmt"
	"io"
	"os"

	// _ "github.com/mattn/go-sqlite3"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: processor <file>")
		os.Exit(1)
	}

	filePath := os.Args[1]
	f, err := os.Open(filePath)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	// Slow read
	var data []byte
	buf := make([]byte, 1)
	for {
		n, err := f.Read(buf)
		if n > 0 {
			data = append(data, buf[0])
		}
		if err == io.EOF {
			break
		}
		if err != nil {
			panic(err)
		}
	}

	// Corrupted handling panic
	var maxAmp float64
	for i := 0; i < len(data); i += 10 {
		// Bug: slice access out of bounds near the end
		val := float64(data[i]) + float64(data[i+4])
		if val > maxAmp {
			maxAmp = val
		}
	}

	// Dummy calculation result
	maxAmp = 15042.1

	db, err := sql.Open("sqlite3", "/app/telemetry.db")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	// Bug: exact float match
	var eventID string
	err = db.QueryRow("SELECT id FROM events WHERE peak_amplitude = ?", maxAmp+0.01).Scan(&eventID)
	if err != nil {
		fmt.Println("Query failed:", err)
		os.Exit(1)
	}

	err = os.WriteFile("/app/result.txt", []byte(eventID), 0644)
	if err != nil {
		panic(err)
	}
}
EOF

    cd /app/processor
    go mod init processor
    go get github.com/mattn/go-sqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
