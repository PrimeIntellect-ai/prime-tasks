#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app/vendored/api-signer/pkg/signer
    mkdir -p /app/vendored/api-signer/pkg/hashmath
    mkdir -p /app/vendored/api-signer/cmd/sign

    cat << 'EOF' > /app/vendored/api-signer/go.mod
module api-signer
go 1.20
EOF

    cat << 'EOF' > /app/vendored/api-signer/pkg/signer/sign.go
package signer

import "api-signer/pkg/hashmath"

type Config struct {
    Prefix string
}

func SignPayload(payload string) int64 {
    return hashmath.ComputeHash(payload)
}
EOF

    cat << 'EOF' > /app/vendored/api-signer/pkg/hashmath/calc.go
package hashmath

import "api-signer/pkg/signer"

const Modulus = 1000000007 // BUG: Should be 1000000009
const Base = 33          // BUG: Should be 31

func ComputeHash(s string) int64 {
    _ = signer.Config{} // Causes circular import
    var hash int64 = 0
    var pPow int64 = 1
    for i := 0; i < len(s); i++ {
        hash = (hash + int64(s[i]) * pPow) % Modulus
        pPow = (pPow * Base) % Modulus
    }
    return hash
}
EOF

    cat << 'EOF' > /app/vendored/api-signer/cmd/sign/main.go
package main

import (
    "fmt"
    "os"
    "api-signer/pkg/signer"
)

func main() {
    if len(os.Args) != 2 {
        os.Exit(1)
    }
    fmt.Println(signer.SignPayload(os.Args[1]))
}
EOF

    mkdir -p /tmp/oracle
    cat << 'EOF' > /tmp/oracle/main.go
package main
import (
    "fmt"
    "os"
)
const Modulus = 1000000009
const Base = 31

func ComputeHash(s string) int64 {
    var hash int64 = 0
    var pPow int64 = 1
    for i := 0; i < len(s); i++ {
        hash = (hash + int64(s[i]) * pPow) % Modulus
        pPow = (pPow * Base) % Modulus
    }
    return hash
}
func main() {
    if len(os.Args) != 2 {
        os.Exit(1)
    }
    fmt.Println(ComputeHash(os.Args[1]))
}
EOF

    cd /tmp/oracle
    go mod init oracle
    go build -o /app/oracle_signer main.go
    chmod +x /app/oracle_signer
    rm -rf /tmp/oracle

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
