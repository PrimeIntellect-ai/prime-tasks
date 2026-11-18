#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

const fakeKey = `-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD9H5X5x7V/O+r4W9l8A0n5Z6mE1l6Q3mY0K9xG6L8D+wAAAJiAAAAAgAAA
...
-----END OPENSSH PRIVATE KEY-----`

func main() {
	http.HandleFunc("/secure/key", func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		parts := strings.Split(token, ".")

		if len(parts) != 3 && len(parts) != 2 {
			http.Error(w, "Invalid token format", http.StatusUnauthorized)
			return
		}

		headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])
		if err != nil {
			http.Error(w, "Invalid header", http.StatusUnauthorized)
			return
		}

		var header map[string]interface{}
		json.Unmarshal(headerJSON, &header)

		payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])
		if err != nil {
			http.Error(w, "Invalid payload", http.StatusUnauthorized)
			return
		}

		var payload map[string]interface{}
		json.Unmarshal(payloadJSON, &payload)

		// Vulnerability: alg "none" bypass
		if header["alg"] == "none" {
			if payload["role"] == "admin" {
				w.WriteHeader(http.StatusOK)
				w.Write([]byte(fakeKey))
				return
			}
		}

		http.Error(w, "Forbidden", http.StatusForbidden)
	})

	fmt.Println("Server running on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/audit.log
[INFO] 2023-10-01T12:00:00Z - Request to /login with username=admin&password=SuperSecretPassword123 from 192.168.1.10
[INFO] 2023-10-01T12:05:00Z - API call to /secure/data header: Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoidXNlciJ9.signature123
[ERROR] 2023-10-01T12:10:00Z - Failed login attempt username=test&password=WrongPassword!
[INFO] 2023-10-01T12:15:00Z - API call to /secure/data header: Authorization: Bearer eyJhbGciOiJub25lIn0.eyJyb2xlIjoiYWRtaW4ifQ.
EOF

    chmod -R 777 /home/user
