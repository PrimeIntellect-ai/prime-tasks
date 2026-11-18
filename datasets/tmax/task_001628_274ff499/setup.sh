#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go git binutils strace ltrace sudo
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.go
package main
import (
    "crypto/sha256"
    "encoding/hex"
    "fmt"
    "os"
)
func main() {
    if len(os.Args) != 4 {
        os.Exit(1)
    }
    data := os.Args[1] + "|" + os.Args[2] + "|" + os.Args[3] + "|SECRET_SALT_8923"
    hash := sha256.Sum256([]byte(data))
    fmt.Print(hex.EncodeToString(hash[:]))
}
EOF
    go build -ldflags="-s -w" -o /app/user_token_bin /tmp/oracle.go
    rm /tmp/oracle.go
    chmod +x /app/user_token_bin

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
