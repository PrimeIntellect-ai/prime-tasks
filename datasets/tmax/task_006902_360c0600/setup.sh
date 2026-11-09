#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang curl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/backend_v1.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Legacy v1 Response: %s", r.URL.Path)
	})
	http.ListenAndServe("127.0.0.1:8081", nil)
}
EOF

    cat << 'EOF' > /home/user/backend_v2.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "New v2 Response: %s", r.URL.Path)
	})
	http.ListenAndServe("127.0.0.1:8082", nil)
}
EOF

    chmod +x /home/user/backend_v1.go /home/user/backend_v2.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
