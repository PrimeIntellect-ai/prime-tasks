#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/server.go
package main

import (
	"fmt"
	"net/http"
)

func handler(w http.ResponseWriter, r *http.Request) {
	// Missing security headers!
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprintf(w, "<html><body><h1>Admin Dashboard</h1></body></html>")
}

func main() {
	http.HandleFunc("/", handler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/wordlist.txt
apple
banana
cherry
admin123
password
supersecret123
qwerty
auditor2023
letmein99
EOF

    cat << 'EOF' > /home/user/setup_enc.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"io"
	"os"
)

func main() {
	password := "supersecret123"
	plaintext := []byte("FLAG{aud1t_p4ss3d_c5p_a3s}")

	hash := sha256.Sum256([]byte(password))
	block, err := aes.NewCipher(hash[:])
	if err != nil {
		panic(err)
	}

	aesgcm, err := cipher.NewGCM(block)
	if err != nil {
		panic(err)
	}

	nonce := make([]byte, 12)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		panic(err)
	}

	ciphertext := aesgcm.Seal(nil, nonce, plaintext, nil)

	finalData := append(nonce, ciphertext...)
	os.WriteFile("/home/user/secrets.enc", finalData, 0644)
}
EOF

    cd /home/user
    go run setup_enc.go
    rm setup_enc.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
