#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl jq
    pip3 install pytest

    mkdir -p /home/user/app
    cd /home/user/app
    go mod init app

    cat << 'EOF' > distance.go
package main

// Levenshtein calculates the Levenshtein distance between two strings.
func Levenshtein(a, b string) int {
	// BUG: incorrect dummy implementation
	diff := len(a) - len(b)
	if diff < 0 {
		return -diff
	}
	return diff
}
EOF

    cat << 'EOF' > main.go
package main

import (
	"fmt"
	"net/http"
)

func main() {
	// TODO: implement REST API on port 8080
	fmt.Println("Server starting on :8080")
	http.ListenAndServe(":8080", nil)
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
