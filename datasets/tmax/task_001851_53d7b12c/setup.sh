#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget tar
    pip3 install pytest

    # Install Go 1.20
    wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/bin/gofmt
    rm go1.20.14.linux-amd64.tar.gz

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/perf-tool

    # Create perf.log
    cat << 'EOF' > /home/user/data/perf.log
1610000000,auth,45.5,1024
1610000001,db,90.2,2048
1610000002,cache,20.0,512
1610000003,api,30.5
1610000004,worker,55.0,1536
EOF

    # Create main.go
    cat << 'EOF' > /home/user/perf-tool/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	_ "github.com/pkg/errors"
)

func main() {
	file, err := os.Open("/home/user/data/perf.log")
	if err != nil {
		panic(err)
	}
	defer file.Close()

	var totalScore float64
	var count int

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, ",")

		// Bug 1: Panics if parts length is less than 4
		cpu, _ := strconv.ParseFloat(parts[2], 64)
		mem, _ := strconv.ParseFloat(parts[3], 64)

		// Bug 2: Formula implementation incorrect.
		// Expected: Score = 50% CPU, 10% Memory
		score := cpu*0.5 + mem*0.01 // Incorrect multiplier here

		totalScore += score
		count++
	}

	// Bug 3: Off-by-one error
	avg := totalScore / float64(count-1)

	fmt.Printf("%.2f\n", avg)
}
EOF

    # Create go.mod
    cat << 'EOF' > /home/user/perf-tool/go.mod
module perf-tool

go 1.20

require github.com/pkg/errors v1.9.9 // Invalid version intentionally
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
