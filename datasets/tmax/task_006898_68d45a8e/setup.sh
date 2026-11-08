#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang-go curl openssl net-tools lsof
pip3 install pytest

mkdir -p /home/user/vnc-api/certs

cat << 'EOF' > /home/user/vnc-api/main.go
package main

import (
	"fmt"
	"net/http"
)

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"service": "vnc-manager", "status": "running", "active_vms": 0}`))
}

func main() {
	http.HandleFunc("/status", statusHandler)

	// Intentionally wrong paths
	certFile := "/etc/ssl/certs/server.crt"
	keyFile := "/etc/ssl/certs/server.key"

	fmt.Println("Starting VNC Manager API on :8443")
	err := http.ListenAndServeTLS(":8443", certFile, keyFile, nil)
	if err != nil {
		panic(err)
	}
}
EOF

# Ensure the dummy process starts when a shell is opened
cat << 'EOF' >> /etc/bash.bashrc
if ! python3 -c 'import socket; s=socket.socket(); s.connect(("127.0.0.1", 8443))' 2>/dev/null; then
    python3 -c "import http.server; http.server.HTTPServer(('', 8443), http.server.SimpleHTTPRequestHandler).serve_forever()" > /dev/null 2>&1 &
fi
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
