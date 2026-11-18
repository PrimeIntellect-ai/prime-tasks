#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/vendored/ffuf

    cat << 'EOF' > /app/vendored/ffuf/main.go
package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	version := flag.Bool("V", false, "Print version")
	flag.Prase() // Deliberate typo

	if *version {
		fmt.Println("ffuf version: 2.0.0")
		os.Exit(0)
	}
	fmt.Println("ffuf running")
}
EOF

    cat << 'EOF' > /app/vendored/ffuf/go.mod
module github.com/ffuf/ffuf

go 1.18
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
