#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget jq
    pip3 install pytest

    # Install Go 1.20
    wget https://go.dev/dl/go1.20.14.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.20.14.linux-amd64.tar.gz
    rm go1.20.14.linux-amd64.tar.gz
    ln -s /usr/local/go/bin/go /usr/local/bin/go
    ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

    mkdir -p /home/user/log_processor
    cd /home/user/log_processor

    cat << 'EOF' > go.mod
module log_processor

go 1.20

require (
	github.com/sirupsen/logrus v1.9.3
	github.com/google/uuid v1.0.0 // This old version lacks features used by the code
)
EOF

    cat << 'EOF' > main.go
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

func main() {
	if len(os.Args) < 3 {
		logrus.Fatal("Usage: processor <input> <output>")
	}

	// Use uuid.NewString() which requires uuid v1.1.0+
	_ = uuid.NewString()

	inFile, err := os.Open(os.Args[1])
	if err != nil {
		logrus.Fatal(err)
	}
	defer inFile.Close()

	var results []map[string]string
	scanner := bufio.NewScanner(inFile)
	for scanner.Scan() {
		line := scanner.Text()
		parsed, err := ParseLogLine(line)
		if err == nil {
			results = append(results, parsed)
		}
	}

	outFile, err := os.Create(os.Args[2])
	if err != nil {
		logrus.Fatal(err)
	}
	defer outFile.Close()

	json.NewEncoder(outFile).Encode(results)
}
EOF

    cat << 'EOF' > parser.go
package main

import (
	"errors"
	"strings"
)

func ParseLogLine(line string) (map[string]string, error) {
	if line == "" {
		return nil, errors.New("empty line")
	}

	res := make(map[string]string)

	// Bug: Doesn't check if strings.Index returns -1 properly for the second quote
	if strings.Contains(line, "\"") {
		firstQuote := strings.Index(line, "\"")
		secondQuote := strings.Index(line[firstQuote+1:], "\"")

		if secondQuote == -1 {
		    // Force a panic by accessing out of bounds length
		    _ = line[len(line)+1] 
		} else {
		    msg := line[firstQuote+1 : firstQuote+1+secondQuote]
		    res["msg"] = msg
		}
	}

	res["raw"] = line
	return res, nil
}
EOF

    cat << 'EOF' > /home/user/raw.log
INFO 2023-10-10 "System started successfully"
WARN 2023-10-10 "High memory usage detected"
ERROR 2023-10-10 "Failed to process filename with spaces unclosed quote
INFO 2023-10-10 "Routine check"
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
