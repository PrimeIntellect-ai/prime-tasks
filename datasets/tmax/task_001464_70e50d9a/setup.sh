#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gcc sqlite3 libsqlite3-dev
    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Generate the SQLite DB
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random

random.seed(42)
conn = sqlite3.connect('/home/user/backup_meta.db')
c = conn.cursor()
c.execute('CREATE TABLE chunks (id INTEGER PRIMARY KEY, size_mb INTEGER, priority_score FLOAT)')
c.execute('CREATE TABLE dependencies (chunk_id INTEGER, depends_on_id INTEGER)')

for i in range(1, 1001):
    c.execute('INSERT INTO chunks VALUES (?, ?, ?)', (i, random.randint(10, 1000), random.uniform(0.1, 5.0)))

edges = set()
while len(edges) < 2000:
    i = random.randint(2, 1000)
    j = random.randint(1, i-1)
    edges.add((i, j))

for i, j in edges:
    c.execute('INSERT INTO dependencies VALUES (?, ?)', (i, j))

conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py
    rm /tmp/gen_db.py

    # Build the eval binary
    cat << 'EOF' > /app/restore_eval.go
package main

import (
	"bufio"
	"database/sql"
	"fmt"
	"os"
	"strconv"

	_ "github.com/mattn/go-sqlite3"
)

type Chunk struct {
	SizeMB        int
	PriorityScore float64
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: restore_eval <plan_file>")
		os.Exit(1)
	}
	planFile := os.Args[1]

	db, err := sql.Open("sqlite3", "/home/user/backup_meta.db")
	if err != nil {
		fmt.Println("Error opening db:", err)
		os.Exit(1)
	}
	defer db.Close()

	chunks := make(map[int]Chunk)
	rows, err := db.Query("SELECT id, size_mb, priority_score FROM chunks")
	if err != nil {
		fmt.Println("Error querying chunks:", err)
		os.Exit(1)
	}
	for rows.Next() {
		var id, size int
		var prio float64
		rows.Scan(&id, &size, &prio)
		chunks[id] = Chunk{size, prio}
	}
	rows.Close()

	deps := make(map[int][]int)
	rows, err = db.Query("SELECT chunk_id, depends_on_id FROM dependencies")
	if err != nil {
		fmt.Println("Error querying deps:", err)
		os.Exit(1)
	}
	for rows.Next() {
		var cid, did int
		rows.Scan(&cid, &did)
		deps[cid] = append(deps[cid], did)
	}
	rows.Close()

	f, err := os.Open(planFile)
	if err != nil {
		fmt.Println("Error opening plan:", err)
		os.Exit(1)
	}
	defer f.Close()

	var sequence []int
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		id, err := strconv.Atoi(scanner.Text())
		if err == nil {
			sequence = append(sequence, id)
		}
	}

	if len(sequence) != len(chunks) {
		fmt.Println("Plan does not contain all chunks")
		os.Exit(1)
	}

	restored := make(map[int]bool)
	var cache []int
	totalCost := 0.0

	for _, id := range sequence {
		for _, dep := range deps[id] {
			if !restored[dep] {
				fmt.Println("Dependency violation")
				os.Exit(1)
			}
		}

		cacheHit := false
		for _, dep := range deps[id] {
			for _, c := range cache {
				if c == dep {
					cacheHit = true
					break
				}
			}
			if cacheHit {
				break
			}
		}

		c := chunks[id]
		cost := float64(c.SizeMB) * (1.0 / c.PriorityScore)
		if cacheHit {
			cost *= 0.5
		}
		totalCost += cost

		restored[id] = true
		cache = append(cache, id)
		if len(cache) > 10 {
			cache = cache[1:]
		}
	}

	fmt.Printf("%.2f\n", totalCost)
}
EOF

    cd /app
    go mod init restore_eval
    go get github.com/mattn/go-sqlite3
    go build -o restore_eval restore_eval.go
    strip restore_eval
    chmod +x restore_eval
    rm restore_eval.go go.mod go.sum

    # Ensure bash is in path for Go
    ln -s /usr/local/go/bin/go /usr/bin/go

    chmod -R 777 /home/user
