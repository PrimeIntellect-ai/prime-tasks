#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang strace
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/batch_data.csv
TX1000,15.99,USD
TX1001,24.50,USD
TX1002,9.99,USD
TX1003,105.00,USD
TX1004,3.50,USD
EOF
    for i in $(seq 5 99); do
        printf "TX10%02d,%d.99,USD\n" $i $((i*2)) >> /home/user/batch_data.csv
    done

    cat << 'EOF' > /home/user/tx-processor.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	var records []string

	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			continue
		}
		// Apply data transformation: append PROCESSED
		transformed := strings.ReplaceAll(line, "USD", "USD-PROCESSED")
		records = append(records, transformed)
	}

	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "error reading input: %v\n", err)
		os.Exit(1)
	}

	// BUG: off-by-one error drops the last record
	for i := 0; i < len(records)-1; i++ {
		fmt.Println(records[i])
	}
}
EOF

    cd /home/user
    go build tx-processor.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
