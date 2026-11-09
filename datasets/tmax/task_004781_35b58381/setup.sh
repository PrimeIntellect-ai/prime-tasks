#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/app.go
package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"
)

func main() {
	user := flag.String("username", "admin", "Database username")
	pass := flag.String("password", "", "Database password")
	flag.Parse()

	if *pass == "" {
		fmt.Println("Error: password required")
		os.Exit(1)
	}

	hash := sha256.Sum256([]byte(*pass))
	fmt.Printf("Connecting user %s with password hash %x\n", *user, hash)
}
EOF

    echo -n "N3dSMEQ0dGlvblBhc3MhMjAyNA==" > /home/user/vault.b64

    chown -R user:user /home/user/app.go /home/user/vault.b64
    chmod 644 /home/user/app.go /home/user/vault.b64

    chmod -R 777 /home/user
