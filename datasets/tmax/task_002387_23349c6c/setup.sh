#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/webapp
    mkdir -p /home/user/hidden

    cat << 'EOF' > /home/user/webapp/config.json
{
  "port": 8080,
  "jwt_secret": "SuperSecretForensicsKey32Bytes!!"
}
EOF

    cat << 'EOF' > /home/user/webapp/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 +0000] "GET / HTTP/1.1" 200 1024
192.168.1.10 - - [10/Oct/2023:13:56:12 +0000] "POST /upload?filename=profile.jpg HTTP/1.1" 200 401
10.0.0.45 - - [10/Oct/2023:14:02:01 +0000] "POST /upload?filename=..%2f..%2fhidden%2fpayload.enc HTTP/1.1" 200 185
192.168.1.11 - - [10/Oct/2023:14:05:00 +0000] "GET /api/status HTTP/1.1" 200 45
EOF

    cat << 'EOF' > /tmp/setup.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"io/ioutil"
	"os"
)

func main() {
	key := []byte("SuperSecretForensicsKey32Bytes!!")
	plaintext := []byte("FLAG{G0_F0r3ns1cs_M4st3r_2024}")

	// Hardcoded nonce for deterministic setup
	nonce := []byte("123456789012")

	block, err := aes.NewCipher(key)
	if err != nil {
		panic(err)
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		panic(err)
	}

	ciphertext := aesgcm.Seal(nil, nonce, plaintext, nil)

	// Final file is nonce + ciphertext
	finalData := append(nonce, ciphertext...)

	os.MkdirAll("/home/user/hidden", 0755)
	ioutil.WriteFile("/home/user/hidden/payload.enc", finalData, 0644)
}
EOF

    go run /tmp/setup.go
    rm /tmp/setup.go

    chmod -R 777 /home/user
