#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang nginx openssl curl
    pip3 install pytest

    mkdir -p /app/compliance_system/auth
    mkdir -p /app/compliance_system/certs
    mkdir -p /app/compliance_system/report

    # Auth service source
    cat << 'EOF' > /app/compliance_system/auth/main.go
package main

import (
	"fmt"
	"net/http"
)

func loginHandler(w http.ResponseWriter, r *http.Request) {
	redirectTo := r.URL.Query().Get("redirect_to")
	if redirectTo == "" {
		redirectTo = "/dashboard"
	}
	http.Redirect(w, r, redirectTo, 302)
}

func main() {
	http.HandleFunc("/login", loginHandler)
	fmt.Println("Listening on 127.0.0.1:8081")
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

    # Report service source and compilation
    cat << 'EOF' > /tmp/report.go
package main

import (
	"fmt"
	"net/http"
)

func auditHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status": "Audit Trail Active"}`))
}

func main() {
	http.HandleFunc("/audit", auditHandler)
	fmt.Println("Listening on 127.0.0.1:9092")
	http.ListenAndServe("127.0.0.1:9092", nil)
}
EOF
    cd /tmp
    go build -o /app/compliance_system/report/report-bin report.go
    rm report.go

    # Certificates
    cd /app/compliance_system/certs
    openssl genrsa -out root.key 2048
    openssl req -x509 -new -nodes -key root.key -sha256 -days 1024 -out root.crt -subj "/C=US/O=Test Root/CN=Test Root CA"

    openssl genrsa -out intermediate.key 2048
    openssl req -new -key intermediate.key -out intermediate.csr -subj "/C=US/O=Test Intermediate/CN=Test Intermediate CA"
    openssl x509 -req -in intermediate.csr -CA root.crt -CAkey root.key -CAcreateserial -out intermediate.crt -days 500 -sha256

    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.csr -subj "/C=US/O=Test Server/CN=localhost"
    openssl x509 -req -in server.csr -CA intermediate.crt -CAkey intermediate.key -CAcreateserial -out leaf.crt -days 500 -sha256

    rm -f root.key server.csr intermediate.csr intermediate.srl root.srl

    # Nginx config
    cat << 'EOF' > /app/compliance_system/nginx.conf
events {}
http {
    server {
        # TODO: Configure SSL and listen on 127.0.0.1:8443

        # TODO: Proxy /login to Auth service

        # TODO: Proxy /audit to Report service
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/compliance_system
