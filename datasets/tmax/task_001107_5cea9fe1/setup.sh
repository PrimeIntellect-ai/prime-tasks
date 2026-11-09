#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 golang-go
    pip3 install pytest

    mkdir -p /home/user
    sqlite3 /home/user/dataset.db <<EOF
CREATE TABLE nodes (id TEXT PRIMARY KEY, label TEXT, name TEXT);
CREATE TABLE edges (source TEXT, target TEXT, relation TEXT);
INSERT INTO nodes VALUES ('n1', 'Author', 'Alice');
INSERT INTO nodes VALUES ('n2', 'Author', 'Bob');
INSERT INTO nodes VALUES ('n3', 'Paper', 'Go Programming');
INSERT INTO nodes VALUES ('n4', 'Concept', 'Concurrency');
INSERT INTO edges VALUES ('n1', 'n3', 'WROTE');
INSERT INTO edges VALUES ('n2', 'n3', 'REVIEWED');
INSERT INTO edges VALUES ('n3', 'n4', 'COVERS');
EOF

    mkdir -p /app
    cat <<'EOF' > /tmp/scorer.go
package main

import (
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("0.0")
		return
	}
	score := 0.0
	for _, arg := range os.Args[1:] {
		score += float64(len(arg))
	}
	fmt.Printf("%.3f\n", score/10.0)
}
EOF
    cd /tmp
    go build -ldflags="-s -w" -o /app/path_scorer scorer.go
    chmod +x /app/path_scorer
    rm /tmp/scorer.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
