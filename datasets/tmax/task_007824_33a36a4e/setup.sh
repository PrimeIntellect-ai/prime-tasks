#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/evidence

    # Generate the certificate
    openssl req -x509 -newkey rsa:2048 -keyout /home/user/evidence/key.pem -out /home/user/evidence/intercepted_cert.pem -days 365 -nodes -subj "/CN=hacked.internal.local" 2>/dev/null

    # Create the malware_server.go file
    cat << 'EOF' > /home/user/evidence/malware_server.go
package main

import (
	"database/sql"
	"fmt"
	"log"
	"net/http"
)

type AuthRequest struct {
	Username string
	Password string
}

func handleAuth(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	err := r.ParseForm()
	if err != nil {
		http.Error(w, "Bad request", http.StatusBadRequest)
		return
	}

	username := r.FormValue("username")
	password := r.FormValue("password")

	// Setup DB connection (mock)
	db, err := sql.Open("sqlite3", "file::memory:")
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// VULNERABLE SQL QUERY (Line 38)
	query := "SELECT id FROM users WHERE username='" + username + "' AND password='" + password + "'"

	rows, err := db.Query(query)
	if err != nil {
		http.Error(w, "Database error", http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	if rows.Next() {
		fmt.Fprintf(w, "Auth Success")
	} else {
		fmt.Fprintf(w, "Auth Failed")
	}
}

func main() {
	http.HandleFunc("/login", handleAuth)
	log.Fatal(http.ListenAndServeTLS(":8443", "intercepted_cert.pem", "key.pem", nil))
}
EOF

    # Create the traffic_logs.txt file
    cat << 'EOF' > /home/user/evidence/traffic_logs.txt
dXNlcm5hbWU9am9obiZwYXNzd29yZD1zZWNyZXQ=
dXNlcm5hbWU9YWxpY2UmcGFzc3dvcmQ9cGFzc3dvcmQxMjM=
dXNlcm5hbWU9YWRtaW4nLS0mcGFzc3dvcmQ9YW55dGhpbmc=
dXNlcm5hbWU9Z3Vlc3QmcGFzc3dvcmQ9Z3Vlc3Q=
EOF

    chmod -R 777 /home/user
