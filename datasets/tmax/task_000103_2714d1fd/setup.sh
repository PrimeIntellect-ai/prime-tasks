#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go espeak
    pip3 install pytest

    mkdir -p /app/data
    espeak -w /app/data/trace_params.wav "The burn in period is exactly one hundred samples. The thinning factor is set to four."

    cat << 'EOF' > /app/oracle_processor_source.go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	burnIn := 100
	thinning := 4

	scanner := bufio.NewScanner(os.Stdin)
	// increase buffer size for long lines
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, 10*1024*1024)

	if !scanner.Scan() {
		return
	}
	parts := strings.Fields(scanner.Text())
	if len(parts) != 2 {
		return
	}
	C, _ := strconv.Atoi(parts[0])
	L, _ := strconv.Atoi(parts[1])

	grandTotal := int64(0)

	for i := 0; i < C; i++ {
		if !scanner.Scan() {
			break
		}
		chainStr := strings.Fields(scanner.Text())
		if len(chainStr) != L {
			continue
		}
		for j := burnIn; j < L; j += thinning {
			val, _ := strconv.ParseInt(chainStr[j], 10, 64)
			grandTotal += val
		}
	}

	fmt.Println(grandTotal)
}
EOF
    go build -o /app/oracle_processor /app/oracle_processor_source.go
    chmod +x /app/oracle_processor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
