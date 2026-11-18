#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip sqlite3 tesseract-ocr wget build-essential
pip3 install pytest pillow

mkdir -p /app
cd /app

# Generate topology image using Python
cat << 'EOF' > gen_img.py
from PIL import Image, ImageDraw
img = Image.new('RGB', (400, 300), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "NodeA-NodeB:5\nNodeA-NodeC:2\nNodeB-MASTER:10\nNodeC-NodeD:3\nNodeD-MASTER:4\nNodeE-NodeD:2\nNodeE-MASTER:15"
d.text((10,10), text, fill=(0,0,0))
img.save('/app/topology.png')
EOF
python3 gen_img.py
rm gen_img.py

# Setup database
sqlite3 /app/backups.db <<EOF
CREATE TABLE backup_logs (id INTEGER PRIMARY KEY, node_id TEXT, timestamp INTEGER, status TEXT, size_bytes INTEGER);
INSERT INTO backup_logs VALUES (1, 'NodeA', 100, 'SUCCESS', 1024);
INSERT INTO backup_logs VALUES (2, 'NodeA', 110, 'FAILED', 0);
INSERT INTO backup_logs VALUES (3, 'NodeA', 120, 'SUCCESS', 2048);
INSERT INTO backup_logs VALUES (4, 'NodeB', 100, 'SUCCESS', 512);
INSERT INTO backup_logs VALUES (5, 'NodeC', 100, 'FAILED', 0);
INSERT INTO backup_logs VALUES (6, 'NodeD', 150, 'SUCCESS', 4096);
INSERT INTO backup_logs VALUES (7, 'NodeE', 160, 'SUCCESS', 8192);
CREATE INDEX idx_backup_status ON backup_logs(status);
EOF

# Install Go 1.21.6
wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
rm go1.21.6.linux-amd64.tar.gz
export PATH=$PATH:/usr/local/go/bin

# Build Oracle
cat << 'EOF' > main.go
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"os"

	_ "github.com/mattn/go-sqlite3"
)

func main() {
	if len(os.Args) != 2 {
		return
	}
	node := os.Args[1]

	costs := map[string]int{
		"NodeA":  9,
		"NodeB":  10,
		"NodeC":  7,
		"NodeD":  4,
		"NodeE":  6,
		"MASTER": 0,
	}

	cost, ok := costs[node]
	if !ok {
		return
	}

	db, err := sql.Open("sqlite3", "/app/backups.db")
	if err != nil {
		return
	}
	defer db.Close()

	var size int
	err = db.QueryRow("SELECT size_bytes FROM backup_logs NOT INDEXED WHERE node_id = ? AND status = 'SUCCESS' ORDER BY timestamp DESC LIMIT 1", node).Scan(&size)
	if err != nil {
		size = 0
	}

	out := map[string]interface{}{
		"node":        node,
		"latest_size": size,
		"route_cost":  cost,
	}
	b, _ := json.Marshal(out)
	fmt.Println(string(b))
}
EOF

go mod init oracle
go get github.com/mattn/go-sqlite3
go build -o /app/oracle_bin main.go
rm main.go go.mod go.sum

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user /app
