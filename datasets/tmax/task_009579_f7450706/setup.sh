#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/service/logs
    mkdir -p /home/user/service/uploads
    mkdir -p /home/user/scripts
    mkdir -p /home/user/etc

    cat << 'EOF' > /home/user/service/token_check.go
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: token_check <token>")
		os.Exit(1)
	}
	token := os.Args[1]

	hash := sha256.Sum256([]byte(token))
	hashStr := hex.EncodeToString(hash[:])

	if hashStr[:2] == "00" {
		os.Exit(0)
	}
	os.Exit(1)
}
EOF

    cat << 'EOF' > /home/user/service/logs/server.log
[2023-10-25T10:00:00Z] 192.168.1.5 - Token: 85 - UploadedPath: image.png
[2023-10-25T10:05:00Z] 10.0.0.2 - Token: 999 - UploadedPath: ../../etc/passwd
[2023-10-25T10:10:00Z] 10.0.0.3 - Token: 214 - UploadedPath: ../../scripts/backdoor.sh
[2023-10-25T10:15:00Z] 10.0.0.4 - Token: 85 - UploadedPath: ../../scripts/readme.txt
[2023-10-25T10:20:00Z] 10.0.0.5 - Token: 214 - UploadedPath: ..%2F..%2Fscripts%2Fshell.sh
EOF

    touch /home/user/service/uploads/image.png
    touch /home/user/etc/passwd
    touch /home/user/scripts/backdoor.sh
    touch /home/user/scripts/readme.txt
    touch /home/user/scripts/shell.sh

    chmod -R 777 /home/user
    chmod -x /home/user/service/uploads/image.png
    chmod -x /home/user/etc/passwd
    chmod -x /home/user/scripts/readme.txt
    chmod +x /home/user/scripts/backdoor.sh
    chmod +x /home/user/scripts/shell.sh
