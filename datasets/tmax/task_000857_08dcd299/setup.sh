#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang git espeak
    pip3 install pytest

    # Generate audio file
    mkdir -p /app
    espeak -w /app/ticket_audio.wav "The backup authorization code is gamma ray burst"

    # Setup git repository
    mkdir -p /app/ticket-service
    cd /app/ticket-service
    git init
    git config --global user.email "dev@example.com"
    git config --global user.name "Dev"

    # Commit 1
    cat << 'EOF' > parser.go
package main

import (
	"time"
)

type AuthRequest struct {
	TicketDate string `json:"ticket_date"`
	Code       string `json:"code"`
}

func parseDate(dateStr string) (time.Time, error) {
	return time.Parse("2006/01/02 15:04:05", dateStr)
}
EOF

    cat << 'EOF' > main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
)

func authHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	apiKey := os.Getenv("API_KEY")
	if apiKey != "sec-99xyz-alpha" {
		http.Error(w, "Unauthorized", http.StatusUnauthorized)
		return
	}

	var req AuthRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	_, err := parseDate(req.TicketDate)
	if err != nil {
		http.Error(w, "Invalid date format", http.StatusBadRequest)
		return
	}

	if req.Code != "gamma ray burst" {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "authenticated"}`))
}

func main() {
	os.Setenv("API_KEY", "sec-99xyz-alpha")
	http.HandleFunc("/auth", authHandler)
	fmt.Println("Server listening on 127.0.0.1:8080")
	http.ListenAndServe("127.0.0.1:8080", nil)
}
EOF

    go mod init ticket-service
    git add .
    git commit -m "Initial commit"

    # Commit 2
    sed -i '/os.Setenv("API_KEY", "sec-99xyz-alpha")/d' main.go
    git add main.go
    git commit -m "Remove hardcoded API key"

    # Commit 3
    sed -i 's|"2006/01/02 15:04:05"|"2006-01-02 15:04:05"|' parser.go
    echo "func missingBracket() {" >> main.go
    git add main.go parser.go
    git commit -m "Update date parsing"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
