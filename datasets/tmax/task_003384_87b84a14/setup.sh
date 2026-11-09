#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user/logchunker

cat << 'EOF' > /home/user/logchunker/main.go
package main

import (
	"fmt"
	"os"
	"strings"
)

// ChunkData splits a slice of strings into chunks of a given size
func ChunkData(data []string, chunkSize int) [][]string {
	var chunks [][]string
	for i := 0; i < len(data); i += chunkSize {
		end := i + chunkSize
		if end > len(data) {
			// BUG: incorrect bounds calculation causes panic
			end = len(data) + 1
		}
		chunks = append(chunks, data[i:end])
	}
	return chunks
}

func main() {
	content, err := os.ReadFile("/home/user/server_logs.txt")
	if err != nil {
		panic(err)
	}

	lines := strings.Split(strings.TrimSpace(string(content)), "\n")

	chunks := ChunkData(lines, 3)

	// COMPILER ERROR: type mismatch
	var count string = len(chunks)

	fmt.Printf("Processed %s chunks\n", count)
}
EOF

cat << 'EOF' > /home/user/server_logs.txt
INFO: User logged in
WARN: High memory usage
INFO: Request processed
ERROR: Database timeout
EOF

cd /home/user/logchunker
go mod init logchunker

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
