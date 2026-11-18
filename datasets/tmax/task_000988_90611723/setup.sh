#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go strace ltrace gdb binutils
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/main.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

func decodeBase64Url(s string) ([]byte, error) {
	s = strings.TrimRight(s, "=")
	return base64.RawURLEncoding.DecodeString(s)
}

func main() {
	if len(os.Args) < 2 {
		return
	}
	input := os.Args[1]
	parts := strings.Split(input, ".")
	if len(parts) != 3 {
		fmt.Printf("{\"error\": \"invalid format\"}\n")
		os.Exit(0)
	}

	headerBytes, err1 := decodeBase64Url(parts[0])
	payloadBytes, err2 := decodeBase64Url(parts[1])

	if err1 != nil || err2 != nil {
		fmt.Printf("{\"error\": \"decode error\"}\n")
		os.Exit(0)
	}

	var header map[string]interface{}
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		fmt.Printf("{\"error\": \"decode error\"}\n")
		os.Exit(0)
	}

	var payload map[string]interface{}
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		fmt.Printf("{\"error\": \"decode error\"}\n")
		os.Exit(0)
	}

	alg, _ := header["alg"].(string)
	if alg != "none" {
		fmt.Printf("{\"status\": \"signature validation failed\"}\n")
		os.Exit(0)
	}

	admin, _ := payload["admin"].(bool)
	user, _ := payload["user"].(string)

	payloadStr := string(payloadBytes)
	injection := false
	if strings.Contains(payloadStr, "<script>") || strings.Contains(payloadStr, "UNION SELECT") || strings.Contains(payloadStr, "' OR 1=1") {
		injection = true
	}

	fmt.Printf("{\"user\": \"%s\", \"admin\": %t, \"escalation_risk\": %t, \"injection_detected\": %t}\n", user, admin, admin, injection)
}
EOF

    cd /app
    go build -ldflags="-s -w" -o legacy_auditor main.go
    rm main.go

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
