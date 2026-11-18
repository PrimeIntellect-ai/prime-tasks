#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip nginx redis-server golang curl openssl
    pip3 install pytest

    mkdir -p /app/nginx /app/certs /app/corpora /app/go-api

    # Generate Certificates
    cd /app/certs
    openssl req -new -x509 -days 365 -nodes -out ca.crt -keyout ca.key -subj "/CN=MyCA"
    openssl req -new -nodes -out server.csr -keyout server.key -subj "/CN=127.0.0.1"
    openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out server.crt -days 365
    openssl req -new -nodes -out client.csr -keyout client.key -subj "/CN=Client"
    openssl x509 -req -in client.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out client.crt -days 365

    # Create Go API
    cat << 'EOF' > /app/go-api/main.go
package main

import (
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"io/ioutil"
	"net/http"
)

func pingHandler(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintf(w, `{"status":"ok"}`)
}

func main() {
	caCert, err := ioutil.ReadFile("/app/certs/ca.crt")
	if err != nil {
		panic(err)
	}
	caCertPool := x509.NewCertPool()
	caCertPool.AppendCertsFromPEM(caCert)

	tlsConfig := &tls.Config{
		ClientCAs:  caCertPool,
		ClientAuth: tls.RequireAndVerifyClientCert,
	}

	server := &http.Server{
		Addr:      ":8443",
		TLSConfig: tlsConfig,
	}

	http.HandleFunc("/ping", pingHandler)
	server.ListenAndServeTLS("/app/certs/server.crt", "/app/certs/server.key")
}
EOF
    cd /app/go-api && go build -o api main.go

    # Create Nginx config
    cat << 'EOF' > /app/nginx/nginx.conf
events {}
http {
    server {
        listen 8080;
        location / {
            proxy_pass http://127.0.0.1:8443;
        }
    }
}
EOF

    # Create Corpora
    cat << 'EOF' > /app/corpora/evil.jsonl
{"request_payload": "%2E%2E%2Fetc%2Fpasswd", "response_body": "ok"}
{"request_payload": "UNION%20SELECT", "response_body": "ok"}
EOF

    cat << 'EOF' > /app/corpora/clean.jsonl
{"request_payload": "hello", "response_body": "My secret is CRED-A1B2-C3D4"}
EOF

    # Setup user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
