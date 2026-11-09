#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/logprocessor/bin
    mkdir -p /home/user/data

    echo "export GOPROXY=http://127.0.0.1:9999" >> /home/user/.bashrc

    cat << 'EOF' > /home/user/logprocessor/go.mod
module logprocessor

go 1.20
EOF

    cat << 'EOF' > /home/user/logprocessor/main.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: logprocessor <logfile>")
		os.Exit(1)
	}

	file, err := os.Open(os.Args[1])
	if err != nil {
		fmt.Printf("Error opening file: %v\n", err)
		os.Exit(1)
	}
	defer file.Close()

	var total float64
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.Split(line, ",")
		if len(parts) < 2 {
			continue
		}

		val, err := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
		if err != nil {
			continue
		}

		total += ConvergeMetric(val)
	}

	if err := scanner.Err(); err != nil {
		fmt.Printf("Error reading file: %v\n", err)
	}

	fmt.Printf("%.4f\n", total)
}
EOF

    cat << 'EOF' > /home/user/logprocessor/processor.go
package main

// ConvergeMetric calculates the square root using Newton-Raphson.
// BUG: Infinite loop for negative numbers.
func ConvergeMetric(v float64) float64 {
	if v == 0 {
		return 0
	}
	x := v
	if x < 0 {
	    x = -x // Bad implementation, actual formula will still oscillate if v is negative
	}
	for {
		next := 0.5 * (x + v/x)
		diff := x - next
		if diff < 0.0001 && diff > -0.0001 {
			return next
		}
		x = next
	}
}
EOF

    cat << 'EOF' > /home/user/data/server.log
INFO, 4.0
WARN, 9.0
ERROR, 16.0
DEBUG, -5.0
INFO, 25.0
EOF

    chmod -R 777 /home/user
