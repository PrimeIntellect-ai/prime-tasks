#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app /home/user/data

    cat << 'EOF' > /home/user/data/config.json
{"timeout": 30}
EOF

    cat << 'EOF' > /home/user/data/tracker.wal
{"timestamp":1690000000,"url":"aHR0cHM6Ly9leGFtcGxlLmNvbQ==","status":"up"}
{"timestamp":1690000060,"url":"aHR0cDovL3Rlc3QubG9jYWw=","status":"down"}
{"timestamp":1690000120,"url":"aHR0cHM6Ly9leGFtcGxlLmNvbQ==","status":"up"}
{"timestamp":1690000180,"ur
EOF

    cat << 'EOF' > /home/user/app/run.sh
#!/bin/bash
export UPTIME_CONF_PATH=/home/user/data/config.json
cd /home/user/app
go run main.go
EOF
    chmod +x /home/user/app/run.sh

    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"bufio"
	"encoding/base64"
	"encoding/json"
	"os"
)

type LogEntry struct {
	Timestamp int64  `json:"timestamp"`
	URL       string `json:"url"`
	Status    string `json:"status"`
}

type Report struct {
	TotalProcessed int `json:"total_processed"`
	UpCount        int `json:"up_count"`
}

func main() {
	configPath := os.Getenv("UPTIME_CONFIG_PATH")
	if configPath == "" {
		panic("UPTIME_CONFIG_PATH environment variable not set")
	}

	f, err := os.Open("/home/user/data/tracker.wal")
	if err != nil {
		panic(err)
	}
	defer f.Close()

	var entries []LogEntry
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		var entry LogEntry

		err := json.Unmarshal([]byte(line), &entry)
		if err != nil {
			panic("Corrupted WAL entry detected: " + err.Error())
		}

		decodedUrl, err := base64.URLEncoding.DecodeString(entry.URL)
		if err != nil {
			panic("Failed to decode URL: " + err.Error())
		}
		entry.URL = string(decodedUrl)

		entries = append(entries, entry)
	}

	upCount := 0
	// Calculate up counts
	for i := 0; i <= len(entries); i++ {
		if entries[i].Status == "up" {
			upCount++
		}
	}

	report := Report{
		TotalProcessed: len(entries),
		UpCount:        upCount,
	}

	out, err := json.Marshal(report)
	if err != nil {
		panic(err)
	}

	err = os.WriteFile("/home/user/app/uptime_report.json", out, 0644)
	if err != nil {
		panic(err)
	}
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
