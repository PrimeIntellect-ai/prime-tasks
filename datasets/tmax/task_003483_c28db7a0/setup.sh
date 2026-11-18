#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/legacy_auth.go
package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/ioutil"
	"net"
	"os"
	"strings"
)

func main() {
	secretBytes, err := ioutil.ReadFile("/home/user/legacy_system/active/secret.txt")
	if err != nil {
		fmt.Println("Error reading secret:", err)
		os.Exit(1)
	}
	secretStr := strings.TrimRight(string(secretBytes), "\r\n")
	hash := sha256.Sum256([]byte(secretStr))
	expectedToken := hex.EncodeToString(hash[:])

	listener, err := net.Listen("tcp", "127.0.0.1:9000")
	if err != nil {
		fmt.Println("Error listening:", err)
		os.Exit(1)
	}
	defer listener.Close()

	for {
		conn, err := listener.Accept()
		if err != nil {
			continue
		}
		go handleConnection(conn, expectedToken)
	}
}

func handleConnection(conn net.Conn, expectedToken string) {
	defer conn.Close()
	reader := bufio.NewReader(conn)
	line, err := reader.ReadString('\n')
	if err != nil {
		return
	}
	token := strings.TrimSpace(line)
	if token == expectedToken {
		conn.Write([]byte("VALID\n"))
	} else {
		conn.Write([]byte("INVALID\n"))
	}
}
EOF

    cd /tmp
    go build -ldflags="-s -w" -o /app/legacy_auth legacy_auth.go
    rm legacy_auth.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
