#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user/logprocessor
    cd /home/user/logprocessor

    cat << 'EOF' > main.go
package main

import (
	"encoding/json"
	"os"
	"strings"
)

type LogEntry struct {
	ID      string `json:"id"`
	Status  string `json:"status"`
	Message string `json:"message"`
	Payload string `json:"payload"`
}

type Uploader interface {
	Upload(status, message string) error
}

func ProcessLogs(filePath string, uploader Uploader) (int, error) {
	data, err := os.ReadFile(filePath)
	if err != nil {
		return 0, err
	}

	lines := strings.Split(string(data), "\n")
	count := 0

	for _, line := range lines {
		if line == "" {
			continue
		}
		var entry LogEntry
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			return 0, err
		}
		if entry.Status == "ERROR" {
			err := uploader.Upload(entry.Status, entry.Message)
			if err != nil {
				return count, err
			}
			count++
		}
	}
	return count, nil
}

func main() {
	// To be implemented by the agent
}
EOF

    cat << 'EOF' > generate.py
import json

with open("data.jsonl", "w") as f:
    for i in range(50000):
        status = "ERROR" if i % 200 == 0 else "INFO"
        entry = {
            "id": str(i),
            "status": status,
            "message": "system event",
            "payload": "A" * 1024 # 1KB payload to bloat memory
        }
        f.write(json.dumps(entry) + "\n")
EOF
    python3 generate.py
    rm generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
