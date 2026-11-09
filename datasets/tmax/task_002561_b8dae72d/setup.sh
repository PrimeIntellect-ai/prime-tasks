#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go docker.io
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/oracle.go
package main

import (
	"os"
	"strings"
)

func main() {
	out := "/tmp/oracle_out.json"
	for _, arg := range os.Args {
		if strings.HasPrefix(arg, "--out=") {
			out = strings.TrimPrefix(arg, "--out=")
		}
	}
	os.WriteFile(out, []byte("[]"), 0644)
}
EOF
    cd /app && go build -ldflags="-s -w" -o path_oracle oracle.go

    mkdir -p /home/user
    cat << 'EOF' > /tmp/gen.py
import csv
import json
import random

accounts = [f"A{i}" for i in range(100)]
with open("/home/user/transactions.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["tx_id","src_account","dst_account","amount","status","timestamp"])
    for i in range(50000):
        writer.writerow([
            f"TX{i}",
            random.choice(accounts),
            random.choice(accounts),
            random.randint(10, 1000),
            random.choice(["completed", "pending", "failed"]),
            "2023-01-01T00:00:00Z"
        ])

queries = [{"src": random.choice(accounts), "dst": random.choice(accounts)} for _ in range(2000)]
with open("/home/user/queries.json", "w") as f:
    json.dump(queries, f)
EOF
    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
