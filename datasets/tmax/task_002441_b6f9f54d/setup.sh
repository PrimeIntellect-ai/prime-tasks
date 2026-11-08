#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics /home/user/certs

    # 1. Generate the Certificate Chain
    cd /home/user/certs
    # Root CA
    openssl req -x509 -newkey rsa:2048 -days 365 -nodes -keyout root.key -out root.crt -subj "/C=US/O=Forensics CA/CN=RootCA"
    # Intermediate CA
    openssl req -newkey rsa:2048 -nodes -keyout intermediate.key -out intermediate.csr -subj "/C=US/O=Forensics CA/CN=IntermediateCA"
    openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -out intermediate.crt -days 365
    # Leaf Cert
    openssl req -newkey rsa:2048 -nodes -keyout leaf.key -out leaf.csr -subj "/C=US/O=Attacker/CN=exfil.malware.local"
    openssl x509 -req -in leaf.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out leaf.crt -days 365

    # 2. Create the malware binary with the hidden string
    cat << 'EOF' > /home/user/forensics/malware.c
#include <stdio.h>
int main() {
    const char* secret = "DECRYPT_KEY_PREFIX=A1B2C3D4E5F67890";
    printf("Running malware...\n");
    return 0;
}
EOF
    gcc /home/user/forensics/malware.c -o /home/user/forensics/malware.bin
    rm /home/user/forensics/malware.c

    # 3. Create the processor.go file with vulnerabilities (CWE-22, CWE-327)
    cat << 'EOF' > /home/user/forensics/processor.go
package main

import (
	"crypto/md5"
	"fmt"
	"io/ioutil"
	"net/http"
	"path/filepath"
)

func processFile(w http.ResponseWriter, r *http.Request) {
	// CWE-22: Path Traversal
	fileName := r.URL.Query().Get("file")
	targetPath := filepath.Join("/var/lib/data", fileName)

	data, err := ioutil.ReadFile(targetPath)
	if err != nil {
		http.Error(w, "File not found", 404)
		return
	}

	// CWE-327: Use of a Broken or Risky Cryptographic Algorithm (MD5)
	hash := md5.Sum(data)
	fmt.Fprintf(w, "File hash: %x\n", hash)
}

func main() {
	http.HandleFunc("/process", processFile)
	http.ListenAndServe(":8080", nil)
}
EOF

    # 4. Generate the encrypted evidence
    cat << 'EOF' > /home/user/forensics/encrypt.go
package main

import (
	"io/ioutil"
)

func main() {
	plaintext := []byte("EVIDENCE_DATA:{user:\"admin_root\",stolen_hash:\"f8b9a1c2d3e4f5a6b7c8d9e0f1a2b3c4\"}")
	key := []byte("A1B2C3D4E5F67890exfil.malware.local")
	ciphertext := make([]byte, len(plaintext))

	for i := 0; i < len(plaintext); i++ {
		ciphertext[i] = plaintext[i] ^ key[i%len(key)]
	}

	ioutil.WriteFile("/home/user/forensics/evidence.enc", ciphertext, 0644)
}
EOF
    cd /home/user/forensics
    go run encrypt.go
    rm encrypt.go

    chmod -R 777 /home/user
