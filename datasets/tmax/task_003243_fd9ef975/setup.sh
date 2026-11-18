#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        ffmpeg \
        tesseract-ocr \
        golang \
        sqlite3 \
        fonts-dejavu-core

    pip3 install pytest

    mkdir -p /app
    cd /app

    # Create video file
    echo -e "CORRUPTED BK-3091\nCORRUPTED BK-4422\nCORRUPTED BK-8819" > /tmp/text.txt
    ffmpeg -f lavfi -i color=c=black:s=640x480:d=2 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:fontsize=30:fontcolor=white:x=10:y=10:textfile=/tmp/text.txt" -c:v libx264 /app/corruption_report.mp4

    # Create database
    sqlite3 /app/backup_meta.db <<EOF
CREATE TABLE servers (server_id INTEGER PRIMARY KEY, hostname TEXT);
CREATE TABLE backups (backup_id TEXT PRIMARY KEY, server_id INTEGER, size_bytes INTEGER, timestamp DATETIME);
CREATE TABLE storage_nodes (node_id INTEGER PRIMARY KEY, backup_id TEXT, location TEXT);

INSERT INTO servers VALUES (1, 'prod-db-01'), (2, 'prod-db-02');
INSERT INTO backups VALUES ('BK-3091', 1, 5000, '2023-01-01'), ('BK-4422', 1, 3000, '2023-01-02'), ('BK-8819', 2, 7000, '2023-01-03'), ('BK-9999', 2, 10000, '2023-01-04');
INSERT INTO storage_nodes VALUES (1, 'BK-3091', 'us-east'), (2, 'BK-3091', 'us-west'), (3, 'BK-4422', 'us-east'), (4, 'BK-8819', 'eu-central'), (5, 'BK-9999', 'eu-central');
EOF

    # Create Go service stub
    cat << 'EOF' > /app/server.go
package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"

	_ "github.com/mattn/go-sqlite3"
)

type Result struct {
	Hostname            string `json:"hostname"`
	TotalCorruptedBytes int64  `json:"total_corrupted_bytes"`
}

func main() {
	http.HandleFunc("/api/v1/corrupted_sizes", func(w http.ResponseWriter, r *http.Request) {
		db, err := sql.Open("sqlite3", "/app/backup_meta.db")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer db.Close()

		// BUGGY QUERY: implicit cross join with storage_nodes
		query := `
		SELECT s.hostname, SUM(b.size_bytes)
		FROM servers s
		JOIN backups b ON s.server_id = b.server_id
		JOIN storage_nodes sn
		WHERE b.backup_id IN ('TODO')
		GROUP BY s.hostname
		ORDER BY s.hostname;
		`

		rows, err := db.Query(query)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()

		var results []Result
		for rows.Next() {
			var res Result
			if err := rows.Scan(&res.Hostname, &res.TotalCorruptedBytes); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			results = append(results, res)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(results)
	})

	log.Fatal(http.ListenAndServe("127.0.0.1:8080", nil))
}
EOF

    # Init Go module
    go mod init app
    go get github.com/mattn/go-sqlite3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
