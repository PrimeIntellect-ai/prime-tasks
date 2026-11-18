#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang sqlite3 build-essential
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    # Create SQLite database
    sqlite3 graph.db <<EOF
CREATE TABLE nodes (id INTEGER PRIMARY KEY, label TEXT);
CREATE TABLE edges (source INTEGER, target INTEGER);

INSERT INTO nodes (id, label) VALUES (1, 'A'), (2, 'B'), (3, 'C'), (4, 'D'), (5, 'E');
INSERT INTO edges (source, target) VALUES (1, 2), (2, 3), (2, 4), (3, 5), (1, 5), (4, 5);
EOF

    # Create Go script with broken query
    cat << 'EOF' > analyze.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"

	_ "github.com/mattn/go-sqlite3"
)

type Result struct {
	ID        int    `json:"node_id"`
	Label     string `json:"node_label"`
	PathCount int    `json:"path_count"`
}

func main() {
	db, err := sql.Open("sqlite3", "./graph.db")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// BUG: Implicit cross join on edges e2
	query := `
		SELECT n.id, n.label, COUNT(e2.target) as path_count
		FROM nodes n, edges e1, edges e2
		WHERE n.id = e1.source
		GROUP BY n.id, n.label
	`

	rows, err := db.Query(query)
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	var results []Result
	for rows.Next() {
		var r Result
		if err := rows.Scan(&r.ID, &r.Label, &r.PathCount); err != nil {
			log.Fatal(err)
		}
		results = append(results, r)
	}

	out, err := json.MarshalIndent(results, "", "  ")
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println(string(out))
}
EOF

    # Create JSON Schema
    cat << 'EOF' > schema.json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "array",
  "items": {
    "type": "object",
    "properties": {
      "node_id": { "type": "integer" },
      "node_label": { "type": "string" },
      "path_count": { "type": "integer" }
    },
    "required": ["node_id", "node_label", "path_count"]
  }
}
EOF

    # Initialize go mod and install sqlite3 dependency
    go mod init graphapp
    go get github.com/mattn/go-sqlite3
    go mod tidy

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
