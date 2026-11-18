#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc golang
    pip3 install pytest

    mkdir -p /home/user/upload_server /home/user/hidden_exfil /tmp/uploads

    cat << 'EOF' > /home/user/upload_server/main.go
package main

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
)

func uploadHandler(w http.ResponseWriter, r *http.Request) {
	fileName := r.URL.Query().Get("filename")
	// Vulnerable to Path Traversal (CWE-22)
	destPath := filepath.Join("/tmp/uploads", fileName)

	outFile, err := os.Create(destPath)
	if err != nil {
		http.Error(w, "Error creating file", http.StatusInternalServerError)
		return
	}
	defer outFile.Close()
	io.Copy(outFile, r.Body)
	w.Write([]byte("Upload successful"))
}

func main() {
	http.HandleFunc("/upload", uploadHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /tmp/implant.c
#include <stdio.h>
int main() {
    char* secret = "JWT_SECRET=f0r3ns1cs_k3y_9981";
    printf("Running implant...\n");
    return 0;
}
EOF
    gcc /tmp/implant.c -o /home/user/hidden_exfil/implant

    cat << 'EOF' > /tmp/make_jwt.py
import hmac, hashlib, base64, json

def b64url(data):
    return base64.urlsafe_b64encode(data).replace(b'=', b'')

header = b64url(json.dumps({"alg":"HS256","typ":"JWT"}).encode())
payload = b64url(json.dumps({"user":"sys_attacker","role":"root"}).encode())
msg = header + b"." + payload
sig = b64url(hmac.new(b"f0r3ns1cs_k3y_9981", msg, hashlib.sha256).digest())
print((msg + b"." + sig).decode())
EOF
    python3 /tmp/make_jwt.py > /home/user/hidden_exfil/token.jwt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
