#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/auth /app/gateway

    cat << 'EOF' > /app/auth/main.go
package main

import (
	"encoding/base64"
	"fmt"
	"net/http"
)

func generateToken(payload string) string {
	bytes := []byte(payload)
	for i := range bytes {
		bytes[i] ^= 0x42
	}
	return base64.StdEncoding.EncodeToString(bytes)
}

func main() {
	http.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		role := r.URL.Query().Get("role")
		if role == "" {
			role = "user"
		}
		token := generateToken("role=" + role)
		fmt.Fprintf(w, "%s", token)
	})
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

    cat << 'EOF' > /app/gateway/main.go
package main

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"strings"
)

func validateToken(token string) bool {
	decoded, err := base64.StdEncoding.DecodeString(token)
	if err != nil {
		return false
	}
	for i := range decoded {
		decoded[i] ^= 0x42
	}
	return strings.Contains(string(decoded), "role=admin")
}

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Welcome to the API Gateway")
	})

	http.HandleFunc("/admin", func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" || !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}
		token := strings.TrimPrefix(authHeader, "Bearer ")
		if validateToken(token) {
			fmt.Fprintf(w, "Admin access granted")
		} else {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
		}
	})

	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
