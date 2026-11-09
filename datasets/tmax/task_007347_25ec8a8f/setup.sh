#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 libsqlite3-dev build-essential
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the CSV data file
    cat << 'EOF' > /home/user/data.csv
id,user_id,event_type,payload
1,101,click,{"button":"login","duration":5}
2,102,view,{"page":"home","duration":10}
3,101,view,{"page":"profile","duration":15}
4,103,click,{"button":"signup","duration":2}
5,102,click,{"button":"submit","duration":8}
6,104,view,{"page":"about","duration":20}
EOF

    # Initialize the Go module
    go mod init eventprocessor
    go get github.com/mattn/go-sqlite3

    # Create the buggy process.go
    cat << 'EOF' > /home/user/process.go
package main

import (
	"database/sql"
	"encoding/csv"
	"fmt"
	"os"
	"sync"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	os.Remove("/home/user/events.db")
	db, err := sql.Open("sqlite3", "/home/user/events.db?_busy_timeout=100")
	if err != nil {
		panic(err)
	}
	defer db.Close()

	_, err = db.Exec(`
		CREATE TABLE users (user_id INTEGER PRIMARY KEY);
		CREATE TABLE events (id INTEGER PRIMARY KEY, user_id INTEGER, event_type TEXT, payload TEXT);
	`)
	if err != nil {
		panic(err)
	}

	file, err := os.Open("/home/user/data.csv")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	reader := csv.NewReader(file)
	records, _ := reader.ReadAll()

	var wg sync.WaitGroup
	// Create an artificial deadlock by reversing transaction insert orders
	for i, record := range records[1:] {
		wg.Add(1)
		go func(i int, rec []string) {
			defer wg.Done()
			tx, _ := db.Begin()
			if i%2 == 0 {
				tx.Exec("INSERT OR IGNORE INTO users (user_id) VALUES (?)", rec[1])
				tx.Exec("INSERT INTO events (id, user_id, event_type, payload) VALUES (?, ?, ?, ?)", rec[0], rec[1], rec[2], rec[3])
			} else {
				tx.Exec("INSERT INTO events (id, user_id, event_type, payload) VALUES (?, ?, ?, ?)", rec[0], rec[1], rec[2], rec[3])
				tx.Exec("INSERT OR IGNORE INTO users (user_id) VALUES (?)", rec[1])
			}
			tx.Commit()
		}(i, record)
	}

	wg.Wait()
	fmt.Println("Ingestion complete")
}
EOF

    chmod -R 777 /home/user
