#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/raw_logs.txt
[INFO] user:101 action:login
[WARN] user:102 action:upload
[ERROR] user:103 action:delete
[INFO] user:104 action:logout
EOF

    cat << 'EOF' > /home/user/processor.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type LogEntry struct {
	Level   string `json:"level"`
	UserID  string `json:"user_id"`
	Action  string `json:"action"`
}

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: processor <input> <output>")
		return
	}

	inFile, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer inFile.Close()

	outFile, err := os.Create(os.Args[2])
	if err != nil {
		panic(err)
	}
	defer outFile.Close()

	// Build error: unused variable
	var count int = 0

	scanner := bufio.NewScanner(inFile)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, " ")
		if len(parts) != 3 {
			continue
		}

		level := strings.Trim(parts[0], "[]")

		// Logic bug: extracting index 0 ("user") instead of index 1 (the actual ID)
		userID := strings.Split(parts[1], ":")[0]

		action := strings.Split(parts[2], ":")[1]

		entry := LogEntry{Level: level, UserID: userID, Action: action}
		data, _ := json.Marshal(entry)
		outFile.WriteString(string(data) + "\n")
	}
}
EOF

    chmod -R 777 /home/user
