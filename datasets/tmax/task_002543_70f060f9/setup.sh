#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/investigation
    cd /home/user/investigation

    # 1. Create the dummy malware.bin
    cat << 'EOF' > malware.go
package main
import "fmt"
func main() {
    key := "AES256KeyForMalwareAnalysis2024!"
    fmt.Println("Running with key:", key[:8]+"...")
}
EOF
    go build -o malware.bin malware.go
    rm malware.go

    # 2. Create the decrypted.log and encrypt it
    cat << 'EOF' > decrypted_original.log
2024-05-10T12:00:00Z | exfil_success | IP: 192.168.1.55 | bytes: 1024
2024-05-10T12:05:00Z | exfil_failed | IP: 10.0.0.1 | bytes: 0
2024-05-10T12:10:00Z | exfil_success | IP: 203.0.113.42 | bytes: 5000
2024-05-10T12:15:00Z | login_attempt | IP: 192.168.1.55 | bytes: 0
2024-05-10T12:20:00Z | exfil_success | IP: 192.168.1.55 | bytes: 2048
2024-05-10T12:25:00Z | exfil_success | IP: 198.51.100.7 | bytes: 128
EOF

    cat << 'EOF' > encrypt.go
package main

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"io"
	"io/ioutil"
	"os"
)

func main() {
	key := []byte("AES256KeyForMalwareAnalysis2024!")
	plaintext, _ := ioutil.ReadFile("decrypted_original.log")

	block, err := aes.NewCipher(key)
	if err != nil { panic(err) }

	aesgcm, err := cipher.NewGCM(block)
	if err != nil { panic(err) }

	nonce := make([]byte, aesgcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil { panic(err) }

	ciphertext := aesgcm.Seal(nil, nonce, plaintext, nil)

	f, _ := os.Create("exfil_data.enc")
	f.Write(nonce)
	f.Write(ciphertext)
	f.Close()
}
EOF
    go run encrypt.go
    rm encrypt.go decrypted_original.log

    # 3. Create the vulnerable server
    cat << 'EOF' > server.go
package main

import (
	"fmt"
	"io/ioutil"
	"net/http"
)

func downloadHandler(w http.ResponseWriter, r *http.Request) {
	filename := r.URL.Query().Get("file")
	if filename == "" {
		http.Error(w, "Missing file parameter", http.StatusBadRequest)
		return
	}

	// VULNERABLE: No path sanitization
	filePath := "/var/www/uploads/" + filename
	content, err := ioutil.ReadFile(filePath)
	if err != nil {
		http.Error(w, "File not found", http.StatusNotFound)
		return
	}

	w.Write(content)
}

func main() {
	http.HandleFunc("/download", downloadHandler)
	fmt.Println("Server listening on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    chmod -R 777 /home/user
