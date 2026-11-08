#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/access.log
192.168.1.50 - - [10/Oct/2023:13:55:36 -0700] "GET /login HTTP/1.1" 200 1024 "-" "Mozilla/5.0"
192.168.1.50 - - [10/Oct/2023:13:58:11 -0700] "POST /login HTTP/1.1" 302 - "-" "Mozilla/5.0" "Set-Cookie: session_id=validuser_991"
10.0.0.99 - - [10/Oct/2023:14:01:12 -0700] "GET /login?redirect=http://attacker.com/steal HTTP/1.1" 302 - "-" "curl/7.68.0" "Set-Cookie: session_id=8f9a2b3c4d5e6f7a"
10.0.0.99 - - [10/Oct/2023:14:01:15 -0700] "POST /api/export HTTP/1.1" 200 4096 "-" "curl/7.68.0" "Cookie: session_id=8f9a2b3c4d5e6f7a"
EOF

    cat << 'EOF' > /home/user/setup.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/sha256"
	"io/ioutil"
)

func main() {
	plaintext := []byte("FLAG{0p3n_r3d1r3ct_t0_c0mpr0m1s3}")
	preimage := "73928f9a2b3c4d5e6f7a"
	key := sha256.Sum256([]byte(preimage))

	block, err := aes.NewCipher(key[:])
	if err != nil {
		panic(err)
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		panic(err)
	}

	nonce := []byte("123456789012") // 12 bytes nonce
	ciphertext := aesgcm.Seal(nil, nonce, plaintext, nil)

	finalData := append(nonce, ciphertext...)
	ioutil.WriteFile("/home/user/exfiltrated.enc", finalData, 0644)
}
EOF

    cd /home/user
    go run setup.go
    rm setup.go

    chmod -R 777 /home/user
