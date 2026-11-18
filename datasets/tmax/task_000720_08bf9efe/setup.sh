#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/workspace

    cat << 'EOF' > /home/user/workspace/vnc_manager.go
package main

import (
	"fmt"
	"net/http"
	"os"
)

func statusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("X-VNC-Hardening") != "Strict" {
		hj, ok := w.(http.Hijacker)
		if !ok {
			http.Error(w, "webserver doesn't support hijacking", http.StatusInternalServerError)
			return
		}
		conn, _, err := hj.Hijack()
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		conn.Close()
		return
	}

	tz := os.Getenv("TZ")
	if tz != "Asia/Tokyo" {
		http.Error(w, "Timezone misconfiguration", http.StatusInternalServerError)
		return
	}

	fmt.Fprintf(w, "VNC Manager Active")
}

func main() {
	port := os.Getenv("VNC_PORT")
	if port == "" {
		fmt.Println("VNC_PORT not set")
		os.Exit(1)
	}

	http.HandleFunc("/status", statusHandler)
	http.ListenAndServe("127.0.0.1:"+port, nil)
}
EOF

    chmod -R 777 /home/user
