#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget curl
    pip3 install pytest aiohttp requests

    # Install Go
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin

    # Create directories
    mkdir -p /home/user/app
    mkdir -p /home/user/scripts

    # Create main.go
    cat << 'EOF' > /home/user/app/main.go
package main

import (
	"encoding/json"
	"fmt"
	"net/http"
)

var jobChan = make(chan string)

func main() {
	http.HandleFunc("/process", handleProcess)
	fmt.Println("Server started on :8080")
	http.ListenAndServe(":8080", nil)
}

func handleProcess(w http.ResponseWriter, r *http.Request) {
	var req map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	data, ok := req["data"].(string)
	if !ok {
		http.Error(w, "bad data", http.StatusBadRequest)
		return
	}

	// This leaks because nothing reads from jobChan
	go func(d string) {
		jobChan <- d
	}(data)

	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"processing"}`))
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
