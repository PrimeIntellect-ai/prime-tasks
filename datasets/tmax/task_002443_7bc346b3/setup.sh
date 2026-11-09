#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang strace
    pip3 install pytest

    mkdir -p /home/user
    mkdir -p /home/user/.config

    cat << 'EOF' > /home/user/calc_engine.go
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	filePath := flag.String("file", "", "Path to WAL file")
	flag.Parse()

	// 1. Check for missing config file (environment misconfig)
	configData, err := os.ReadFile("/home/user/.config/math_init.conf")
	if err != nil {
		os.Exit(1)
	}

	state, err := strconv.ParseFloat(strings.TrimSpace(string(configData)), 64)
	if err != nil {
		os.Exit(1)
	}

	if *filePath == "" {
		fmt.Println("No file provided")
		os.Exit(1)
	}

	file, err := os.Open(*filePath)
	if err != nil {
		os.Exit(1)
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		parts := strings.Split(line, " ")
		if len(parts) != 2 {
			panic("Parse error: invalid token count")
		}

		op := parts[0]
		val, err := strconv.ParseFloat(parts[1], 64)
		if err != nil {
			panic("Parse error: invalid float format")
		}

		switch op {
		case "ADD":
			state += val
		case "SUB":
			state -= val
		case "MUL":
			state *= val
		case "DIV":
			state /= val
		default:
			panic("Parse error: unknown operation")
		}
	}

	fmt.Printf("%.2f\n", state)
}
EOF

    cd /home/user
    go build -o calc_engine calc_engine.go
    rm calc_engine.go

    cat << 'EOF' > /home/user/tx.wal
ADD 50.0
MUL 2.0
ADD 12.5x
SUB 25.0
UNKNOWN 10.0
ADD 10.0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
