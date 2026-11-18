#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/api_server.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

type User struct {
	ID         int    `json:"id"`
	Name       string `json:"name"`
	Email      string `json:"email"`
	CreditCard string `json:"credit_card"`
}

func main() {
	http.HandleFunc("/api/users", func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("Authorization")
		if !strings.HasPrefix(authHeader, "Bearer ") {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(authHeader, "Bearer ")
		parts := strings.Split(token, ".")
		if len(parts) != 3 {
			http.Error(w, "Malformed token", http.StatusUnauthorized)
			return
		}

		headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
		if err != nil {
			http.Error(w, "Invalid header", http.StatusUnauthorized)
			return
		}

		var header map[string]interface{}
		json.Unmarshal(headerBytes, &header)

		if alg, ok := header["alg"].(string); !ok || strings.ToLower(alg) != "none" {
			http.Error(w, "Forbidden: Only 'none' alg supported in this vulnerable mock", http.StatusForbidden)
			return
		}

		payloadBytes, err := base64.RawURLEncoding.DecodeString(parts[1])
		if err != nil {
			http.Error(w, "Invalid payload", http.StatusUnauthorized)
			return
		}

		var payload map[string]interface{}
		json.Unmarshal(payloadBytes, &payload)

		if role, ok := payload["role"].(string); !ok || role != "admin" {
			http.Error(w, "Forbidden: Admin access required", http.StatusForbidden)
			return
		}

		// Vulnerable endpoint data
		users := []User{
			{ID: 1, Name: "Alice Smith", Email: "alice@example.com", CreditCard: "4111222233334444"},
			{ID: 2, Name: "Bob Jones", Email: "bob@example.com", CreditCard: "5500000000001234"},
			{ID: 3, Name: "Charlie Brown", Email: "charlie@example.com", CreditCard: "6011000000005678"},
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(users)
	})

	fmt.Println("Server listening on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/expected_redacted.json
[
  {
    "id": 1,
    "name": "Alice Smith",
    "email": "alice@example.com",
    "credit_card": "************4444"
  },
  {
    "id": 2,
    "name": "Bob Jones",
    "email": "bob@example.com",
    "credit_card": "************1234"
  },
  {
    "id": 3,
    "name": "Charlie Brown",
    "email": "charlie@example.com",
    "credit_card": "************5678"
  }
]
EOF

    chmod -R 777 /home/user
