#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang util-linux
    pip3 install pytest

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/auth_server.go
package main

import (
	"fmt"
	"net/http"
)

func loginHandler(w http.ResponseWriter, r *http.Request) {
	password := r.FormValue("password")
	next := r.URL.Query().Get("next")
	if next == "" {
		next = "/dashboard"
	}

	// Legacy auth
	if password == "supersecret_legacy" {
		// Vulnerable open redirect
		http.Redirect(w, r, next, http.StatusFound)
		return
	}

	http.Error(w, "Unauthorized", http.StatusUnauthorized)
}

func main() {
	http.HandleFunc("/login", loginHandler)
	fmt.Println("Server running on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/app/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?next=/profile HTTP/1.1" 200 1024
10.0.0.5 - - [10/Oct/2023:14:01:12 -0700] "POST /login?next=http://evil.com/phish HTTP/1.1" 302 0
192.168.1.15 - - [10/Oct/2023:14:05:00 -0700] "POST /login?next=/settings HTTP/1.1" 302 0
203.0.113.42 - - [10/Oct/2023:14:10:22 -0700] "POST /login?next=https://attacker.net/malware HTTP/1.1" 302 0
203.0.113.42 - - [10/Oct/2023:14:15:33 -0700] "POST /login?next=https://attacker.net/malware HTTP/1.1" 302 0
10.0.0.5 - - [10/Oct/2023:14:20:11 -0700] "POST /login?next=http://evil.com/phish HTTP/1.1" 401 50
198.51.100.7 - - [10/Oct/2023:14:25:01 -0700] "POST /login?next=//malicious.com HTTP/1.1" 302 0
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/app
    chmod 644 /home/user/app/auth_server.go
    chmod 644 /home/user/app/access.log
    chmod -R 777 /home/user
