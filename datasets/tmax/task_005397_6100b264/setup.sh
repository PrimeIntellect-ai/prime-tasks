#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git wget
    pip3 install pytest

    # Create workspace and app directories
    mkdir -p /app/vendor/github.com/buger
    mkdir -p /app/backup/bytesafe
    mkdir -p /home/user/workspace/dataparser
    mkdir -p /home/user/raw_data
    mkdir -p /home/user/organized_datasets

    # Setup the vendored package
    cd /app/vendor/github.com/buger
    git clone --branch v1.1.1 https://github.com/buger/jsonparser.git
    cd jsonparser

    # Introduce perturbation 1: Corrupted import
    sed -i 's|import (|import (\n\t"math/rand/v2"|' parser.go

    # Introduce perturbation 2: Broken symlink for bytesafe
    ln -s /tmp/bytesafe_bak /app/vendor/github.com/buger/jsonparser/bytesafe

    # Setup the main Go workspace
    cd /home/user/workspace/dataparser
    go mod init dataparser
    go mod edit -require github.com/buger/jsonparser@v1.1.1

    # Link the vendor directory
    ln -s /app/vendor /home/user/workspace/dataparser/vendor

    # Create vendor/modules.txt
    cat << 'EOF' > /app/vendor/modules.txt
# github.com/buger/jsonparser v1.1.1
## explicit
github.com/buger/jsonparser
EOF

    # Create the Go program
    cat << 'EOF' > /home/user/workspace/dataparser/main.go
package main

import (
	"bufio"
	"fmt"
	"os"

	"github.com/buger/jsonparser"
)

func main() {
	scanner := bufio.NewScanner(os.Stdin)
	fmt.Println("timestamp,sensor_id,reading_value")
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		ts, _, _, err := jsonparser.Get(line, "timestamp")
		if err != nil {
			continue
		}
		sid, _, _, err := jsonparser.Get(line, "sensor_id")
		if err != nil {
			continue
		}
		val, _, _, err := jsonparser.Get(line, "reading_value")
		if err != nil {
			continue
		}
		fmt.Printf("%s,%s,%s\n", string(ts), string(sid), string(val))
	}
}
EOF

    # Generate the JSONL data
    cat << 'EOF' > /tmp/gen_data.py
import json
import random

with open('/home/user/raw_data/sensors.jsonl', 'w') as f:
    for i in range(5500):
        if i % 11 == 0:
            f.write("DEBUG_MACRO:: some debug info\n")
        else:
            val = round(random.uniform(10.0, 50.0), 2)
            f.write(json.dumps({"timestamp": "2023-10-01T12:00:00Z", "sensor_id": f"sensor_{i}", "reading_value": val}) + "\n")
EOF
    python3 /tmp/gen_data.py
    rm /tmp/gen_data.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user /app
