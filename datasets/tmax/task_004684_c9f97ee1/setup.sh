#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang openssl curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cd /home/user
    openssl req -x509 -newkey rsa:4096 -days 365 -nodes -keyout ca.key -out ca.crt -subj "/CN=InternalCA"
    openssl req -newkey rsa:4096 -nodes -keyout server.key -out server.csr -subj "/CN=127.0.0.1"
    cat <<EOF > extfile.cnf
subjectAltName=IP:127.0.0.1
EOF
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365 -extfile extfile.cnf

    cat <<'EOF' > /home/user/server.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"log"
)

func configHandler(w http.ResponseWriter, r *http.Request) {
	authHeader := r.Header.Get("Authorization")
	if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	token := strings.TrimPrefix(authHeader, "Bearer ")
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		http.Error(w, "Invalid token format", http.StatusUnauthorized)
		return
	}

	headerBytes, _ := base64.RawURLEncoding.DecodeString(parts[0])
	var header map[string]interface{}
	json.Unmarshal(headerBytes, &header)

	if header["alg"] != "none" {
		http.Error(w, "Only 'none' alg supported in this vulnerable mock", http.StatusUnauthorized)
		return
	}

	payloadBytes, _ := base64.RawURLEncoding.DecodeString(parts[1])
	var payload map[string]interface{}
	json.Unmarshal(payloadBytes, &payload)

	if payload["role"] != "admin" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	// Vulnerable cookie (missing HttpOnly and Secure)
	http.SetCookie(w, &http.Cookie{
		Name:  "session_id",
		Value: "mock_session_12345",
		Path:  "/",
	})

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{
		"sshd_config": "Port 22\nPermitRootLogin yes\nPasswordAuthentication yes\nAllowTcpForwarding no",
		"status":      "success",
	})
}

func main() {
	http.HandleFunc("/api/ssh-config", configHandler)
	log.Fatal(http.ListenAndServeTLS("127.0.0.1:8443", "server.crt", "server.key", nil))
}
EOF

    go build -o vuln_server server.go

    # Start the server when a bash session starts
    echo "if ! pgrep -x vuln_server > /dev/null; then cd /home/user && ./vuln_server & sleep 2; fi" >> /home/user/.bashrc
    echo "if ! pgrep -x vuln_server > /dev/null; then cd /home/user && ./vuln_server & sleep 2; fi" >> /root/.bashrc

    chmod -R 777 /home/user
