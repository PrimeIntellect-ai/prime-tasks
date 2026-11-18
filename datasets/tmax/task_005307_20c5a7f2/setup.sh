#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/obfuscator.go
package main

import (
    "crypto/rsa"
    "crypto/sha256"
    "crypto/x509"
    "encoding/base64"
    "encoding/hex"
    "encoding/pem"
    "fmt"
    "io/ioutil"
    "os"
)

func main() {
    if len(os.Args) != 3 {
        os.Exit(1)
    }
    certBytes, err := ioutil.ReadFile(os.Args[1])
    if err != nil {
        os.Exit(1)
    }
    block, _ := pem.Decode(certBytes)
    if block == nil {
        os.Exit(1)
    }
    cert, err := x509.ParseCertificate(block.Bytes)
    if err != nil {
        os.Exit(1)
    }
    rsaPub, ok := cert.PublicKey.(*rsa.PublicKey)
    if !ok {
        os.Exit(1)
    }
    modulus := rsaPub.N.Bytes()
    hash := sha256.Sum256(modulus)

    payload := os.Args[2]
    b64 := base64.StdEncoding.EncodeToString([]byte(payload))

    out := make([]byte, len(b64))
    for i := 0; i < len(b64); i++ {
        out[i] = b64[i] ^ hash[i%32]
    }
    fmt.Print(hex.EncodeToString(out))
}
EOF

    go build -ldflags="-s -w" -o /app/obfuscator_bin /tmp/obfuscator.go
    rm /tmp/obfuscator.go

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/deploy_payload.sh
#!/bin/bash
sudo /app/obfuscator_bin /etc/ssl/certs/target.pem "$1" &
EOF
    chmod +x /home/user/deploy_payload.sh

    chmod -R 777 /home/user
