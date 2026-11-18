#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_server.go
package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
)

func verifyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Pin string `json:"pin"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	salt := "audit_salt_"
	hash := sha256.Sum256([]byte(salt + req.Pin))
	hashStr := hex.EncodeToString(hash[:])

	targetHash := "78ea7f858fa3914a844fcbfd70a41f6e2fde431522f1c84f686940a831e3d6e5"

	w.Header().Set("Content-Type", "application/json")
	if hashStr == targetHash {
		fmt.Fprint(w, `{"status":"success","token":"COMPLIANCE_TOKEN_A8F92C"}`)
	} else {
		w.WriteHeader(http.StatusUnauthorized)
		fmt.Fprint(w, `{"status":"error","message":"invalid pin"}`)
	}
}

func main() {
	http.HandleFunc("/verify", verifyHandler)
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    chmod -R 777 /home/user
