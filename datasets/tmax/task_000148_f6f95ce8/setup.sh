#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl strace binutils
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/main.go
package main

import (
	"fmt"
	"net/http"
	"os"
	"os/exec"
)

func main() {
	port := os.Getenv("GATEWAY_PORT")
	token := os.Getenv("GATEWAY_TOKEN")
	dataDir := os.Getenv("GATEWAY_DATA_DIR")

	if port == "" || token == "" || dataDir == "" {
		fmt.Println("Missing environment variables")
		os.Exit(1)
	}

	_, err := exec.LookPath("curl")
	if err != nil {
		fmt.Println("curl not found in PATH")
		os.Exit(1)
	}

	http.HandleFunc("/status", func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if auth == "Bearer "+token {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("OK"))
		} else {
			w.WriteHeader(http.StatusUnauthorized)
		}
	})

	addr := "127.0.0.1:" + port
	http.ListenAndServe(addr, nil)
}
EOF

    go build -ldflags="-s -w" -o /app/telemetry_gateway /tmp/main.go
    rm /tmp/main.go

    useradd -m -s /bin/bash user || true

    mkdir -p /opt/custom_empty_bin
    cat << 'EOF' > /home/user/start_service.sh
#!/bin/bash
# Broken wrapper
export PATH="/opt/custom_empty_bin"
# missing env vars
/app/telemetry_gateway &
EOF
    chmod +x /home/user/start_service.sh

    chmod -R 777 /home/user
