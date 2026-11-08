#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go coreutils
    pip3 install pytest

    mkdir -p /home/user/payloads
    mkdir -p /home/user/service

    # Create 100 payload files
    for i in $(seq -w 000 099); do
        if [ "$i" = "042" ]; then
            head -c 12 /dev/urandom > /home/user/payloads/${i}.dat
        else
            head -c 16 /dev/urandom > /home/user/payloads/${i}.dat
        fi
    done

    # Create the buggy Go source code
    cat << 'EOF' > /home/user/service/processor.go
package main

import (
	"os"
	"path/filepath"
	"sort"
)

func main() {
	files, err := filepath.Glob("/home/user/payloads/*.dat")
	if err != nil {
		os.Exit(1)
	}
	sort.Strings(files)

	// Truncate/create the log file
	fLog, err := os.OpenFile("/home/user/service/processed.log", os.O_TRUNC|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		os.Exit(1)
	}
	defer fLog.Close()

	for _, file := range files {
		data, err := os.ReadFile(file)
		if err != nil {
			continue
		}

		processPayload(data)
		fLog.WriteString(file + "\n")
	}
}

func processPayload(data []byte) {
	// BUG: off-by-one / boundary condition. 
	// If len(data) is not a multiple of 8, the last iteration will panic with index out of bounds.
	for i := 0; i < len(data); i += 8 {
		chunk := data[i : i+8]
		_ = chunk // simulate processing
	}
}
EOF

    cd /home/user/service
    go build -o processor processor.go

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
