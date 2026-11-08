#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git make
    pip3 install pytest

    # Create log-sanitiser directory and skeleton
    mkdir -p /home/user/log-sanitiser
    cat << 'EOF' > /home/user/log-sanitiser/main.go
package main

import (
	"fmt"
	"os"
)

func main() {
	// Implement sanitiser here
}
EOF

    cat << 'EOF' > /home/user/log-sanitiser/go.mod
module log-sanitiser

go 1.18

require github.com/buger/jsonparser v1.1.1

replace github.com/buger/jsonparser => /app/vendor/github.com/buger/jsonparser
EOF

    # Setup vendored package
    mkdir -p /app/vendor/github.com/buger
    cd /app/vendor/github.com/buger
    git clone -b v1.1.1 https://github.com/buger/jsonparser.git
    cd jsonparser

    # Inject perturbation into Makefile
    if [ -f Makefile ]; then
        sed -i 's/go test/GOOS=windows go test/g' Makefile
        echo -e "\nbuild:\n\tGOOS=windows go build ./..." >> Makefile
    else
        echo -e "build:\n\tGOOS=windows go build ./..." > Makefile
    fi

    # Create corpus directories and files
    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    cat << 'EOF' > /home/user/corpus/clean/clean1.log
{"metric_name": "cpu_usage", "metric_value": 45.2, "host": "srv1"}
{"metric_name": "mem_usage", "metric_value": 80.1, "host": "srv2"}
EOF

    cat << 'EOF' > /home/user/corpus/evil/evil1.log
{"metric_name": "cpu_usage_DROP_ME", "metric_value": 45.2}
{"metric_name": "mem", "metric_value": "high"}
{"metric_name": "disk"}
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
