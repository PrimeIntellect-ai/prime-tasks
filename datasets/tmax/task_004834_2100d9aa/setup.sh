#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required system packages
apt-get install -y supervisor openssh-server openssh-client golang binutils

# Create the operator-core binary
mkdir -p /app
cat << 'EOF' > /tmp/operator.go
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
)

func main() {
	port := flag.Int("port", 8080, "Port to listen on")
	flag.Parse()

	http.HandleFunc("/api/v1/manifests", func(w http.ResponseWriter, r *http.Request) {
		authHeader := r.Header.Get("X-K8s-Mock-Auth")
		if authHeader != "k8s-mock-alpha-99x2" {
			http.Error(w, "Unauthorized", http.StatusUnauthorized)
			return
		}

		resp := map[string]string{
			"status": "success",
			"backend": fmt.Sprintf("port-%d", *port),
			"data": "manifest-list",
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(resp)
	})

	fmt.Printf("Listening on %d\n", *port)
	http.ListenAndServe(fmt.Sprintf("127.0.0.1:%d", *port), nil)
}
EOF

# Build the stripped binary
go build -ldflags="-s -w" -o /app/operator-core /tmp/operator.go
chmod +x /app/operator-core
rm /tmp/operator.go

# Setup sshd run directory
mkdir -p /run/sshd

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
