#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/queries.txt
0.005
0.012
0.008
120.0
0.001
EOF

    cat << 'EOF' > /home/user/container_logs.txt
[INFO] Container started
[INFO] Processing batch queries...
Processing query 1 (target: 0.005)
Success: 0.005000
Processing query 2 (target: 0.012)
Success: 0.012000
Processing query 3 (target: 0.008)
Success: 0.008000
Processing query 4 (target: 120)
[WARN] Health check timeout - killing process...
EOF

    cat << 'EOF' > /home/user/processor.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: processor <queries_file>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	queryID := 1
	for scanner.Scan() {
		val, _ := strconv.ParseFloat(scanner.Text(), 32)
		target := float32(val)

		fmt.Printf("Processing query %d (target: %v)\n", queryID, target)

		var current float32 = 0.0
		var step float32 = 0.00001

		// Vulnerable loop: precision loss causes an infinite loop for large targets
		for current < target {
			next := current + step
			if next == current {
				// Precision loss livelock!
				panic("Livelock detected: step is too small to increment current value")
			}
			current = next
		}
		fmt.Printf("Success: %f\n", current)
		queryID++
	}
}
EOF

    chmod +x /home/user/processor.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
