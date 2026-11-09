#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git openssh-server make
    pip3 install pytest

    mkdir -p /app/git-sre-hook-1.0.0

    cat << 'EOF' > /app/git-sre-hook-1.0.0/main.go
package main

import (
	"fmt"
	"os"
)

func main() {
	port := os.Getenv("SSH_PRT")
	fmt.Println("Checking port:", port)
}
EOF

    cat << 'EOF' > /app/git-sre-hook-1.0.0/Makefile
build:
    go build -o hook main.go
EOF

    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    echo "sshd[123]: Authentication refused: bad ownership or modes for directory /home/user/.ssh" > /app/corpora/evil/1.log
    echo "sshd[124]: Accepted publickey for user from 192.168.1.1" > /app/corpora/clean/1.log

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
