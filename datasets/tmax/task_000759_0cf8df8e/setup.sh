#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Initialize go module
    go mod init etl
    go get github.com/mattn/go-sqlite3

    # Create source.csv
    cat << 'EOF' > source.csv
event_id,user_id,event_type,timestamp
evt_001,user_123A,click,2023-10-25T14:30:00Z
evt_002,user_456C,view,2023-10-25T15:00:00Z
evt_003,user_789B,click,2023-10-28T09:15:00Z
evt_004,user_000A,purchase,invalid_date_format
evt_005,user_111B,view,2023-10-29T23:45:00Z
evt_006,user_222A,click,2023-10-26T10:00:00Z
evt_007,user_333D,view,2023-10-26T11:00:00Z
evt_008,user_444B,click,not_a_date
evt_009,user_555A,purchase,2023-10-21T02:00:00Z
EOF

    # Create SQLite database and table
    sqlite3 data.db "CREATE TABLE events (event_id TEXT PRIMARY KEY, user_id TEXT, event_type TEXT, timestamp TEXT, hour INTEGER, is_weekend BOOLEAN);"

    # Pre-insert a duplicate to test idempotency
    sqlite3 data.db "INSERT INTO events (event_id, user_id, event_type, timestamp, hour, is_weekend) VALUES ('evt_001', 'user_123A', 'click', '2023-10-25T14:30:00Z', 14, 0);"

    # Create the buggy etl.go template
    cat << 'EOF' > etl.go
package main

import (
	"database/sql"
	"encoding/csv"
	"fmt"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	db, err := sql.Open("sqlite3", "./data.db")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	file, err := os.Open("source.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, err := reader.ReadAll()
	if err != nil {
		panic(err)
	}

	for i, record := range records {
		if i == 0 {
			continue // skip header
		}

		eventID := record[0]
		userID := record[1]
		eventType := record[2]
		timestamp := record[3]

		// Bug 1: No error handling for timestamp, just panics if we try to parse
		// Bug 2: Insert is not idempotent
		// Bug 3: Missing sampling and feature extraction

		_, err = db.Exec("INSERT INTO events (event_id, user_id, event_type, timestamp, hour, is_weekend) VALUES (?, ?, ?, ?, ?, ?)", 
			eventID, userID, eventType, timestamp, 0, false)

		if err != nil {
			panic(fmt.Sprintf("Failed to insert %s: %v", eventID, err))
		}
	}
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
