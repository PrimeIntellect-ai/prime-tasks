#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget gcc sqlite3
    pip3 install pytest

    # Install Go 1.21+ to support go-sqlite3
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    rm go1.21.6.linux-amd64.tar.gz

    useradd -m -s /bin/bash user || true

    # Generate raw_subs.csv
    cat << 'EOF' > /tmp/gen_data.py
import csv, random
random.seed(42)
with open('/home/user/raw_subs.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(['id', 'start_ms', 'end_ms', 'raw_text'])
    current_time = 1000
    for i in range(1, 10001):
        duration = random.randint(1500, 3000)
        start = current_time
        end = current_time + duration

        if random.random() < 0.2 and i > 1 and i < 10000:
            start_out, end_out = -1, -1
        else:
            start_out, end_out = start, end

        text = f"<i>Hello</i> WORLD, this is line {i}! <font color='red'>Testing...</font>"
        writer.writerow([i, start_out, end_out, text])
        current_time = end + random.randint(100, 500)
EOF
    python3 /tmp/gen_data.py

    # Create evaluator binary
    mkdir -p /app
    cat << 'EOF' > /app/eval_lqs.go
package main
import (
    "database/sql"
    "fmt"
    "os"
    "strings"
    _ "github.com/mattn/go-sqlite3"
)

func main() {
    if len(os.Args) < 2 { os.Exit(1) }
    db, err := sql.Open("sqlite3", os.Args[1])
    if err != nil { fmt.Println("0.0"); return }
    defer db.Close()

    rows, err := db.Query("SELECT id, start_ms, end_ms, text FROM subtitles ORDER BY id ASC")
    if err != nil { fmt.Println("0.0"); return }

    total := 0
    var correct float64 = 0.0
    var prevEnd int = -1
    for rows.Next() {
        var id, start, end int
        var text string
        rows.Scan(&id, &start, &end, &text)
        total++

        score := 1.0
        if start <= prevEnd && prevEnd != -1 { score -= 0.5 }
        if end <= start { score -= 0.5 }
        if strings.Contains(text, "<") || strings.Contains(text, "!") || text != strings.ToLower(text) { score -= 0.5 }

        if score > 0 { correct += score }
        prevEnd = end
    }

    fmt.Printf("%.4f\n", float64(correct)/float64(total))
}
EOF

    cd /app
    go mod init eval
    go get github.com/mattn/go-sqlite3
    go build -ldflags="-s -w" -o /app/eval_lqs eval_lqs.go
    strip /app/eval_lqs

    # Ensure Go binary is available to the user if they need it
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /home/user/.bashrc

    chmod -R 777 /home/user
    chmod -R 777 /app
