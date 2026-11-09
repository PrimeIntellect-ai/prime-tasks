#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang binutils
    pip3 install pytest

    mkdir -p /home/user/pipeline/bin
    mkdir -p /home/user/pipeline/dumps
    mkdir -p /home/user/pipeline/data

    cat << 'EOF' > /tmp/logparser.go
package main
import "os"
import "fmt"
func main() {
    if os.Getenv("X_PIPELINE_AUTH_KEY_V2") == "" {
        fmt.Println("Error: Missing required environment variable.")
        os.Exit(1)
    }
    fmt.Println("Service running...")
}
EOF
    go build -o /home/user/pipeline/bin/logparser /tmp/logparser.go
    rm /tmp/logparser.go

    head -c 1024 /dev/urandom > /home/user/pipeline/dumps/core.dump
    echo -n "CS_8x99y2z1a4" >> /home/user/pipeline/dumps/core.dump
    head -c 1024 /dev/urandom >> /home/user/pipeline/dumps/core.dump

    cat << 'EOF' > /home/user/pipeline/data/input.log
[INFO] Connection established
[DEBUG] Retrying block 1
[AUTH] User login successful CS_8x99y2z1a4
[ERROR] Timeout on endpoint
[AUTH] Token refreshed CS_8x99y2z1a4
[INFO] Shutting down
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
