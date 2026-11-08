#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/validator.go
package main

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"os"
	"strings"
)

type Header struct {
	Alg string `json:"alg"`
}

type Payload struct {
	User string `json:"user"`
	Role string `json:"role"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: validator <token>")
		return
	}
	token := os.Args[1]
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		fmt.Println("Invalid token format")
		return
	}

	headerBytes, err1 := base64.RawURLEncoding.DecodeString(parts[0])
	payloadBytes, err2 := base64.RawURLEncoding.DecodeString(parts[1])
	if err1 != nil || err2 != nil {
		fmt.Println("Invalid encoding")
		return
	}
	signature := parts[2]

	var header Header
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		fmt.Println("Invalid header JSON")
		return
	}

	// Vulnerability: accepts "none" algorithm to bypass signature verification
	if header.Alg != "none" {
		mac := hmac.New(sha256.New, []byte("super_secret_unpredictable_key_999"))
		mac.Write([]byte(parts[0] + "." + parts[1]))
		expectedMAC := mac.Sum(nil)
		expectedSignature := base64.RawURLEncoding.EncodeToString(expectedMAC)
		if signature != expectedSignature {
			fmt.Println("Invalid signature")
			return
		}
	} else {
		if signature != "" {
			fmt.Println("Invalid signature for none alg")
			return
		}
	}

	var payload Payload
	if err := json.Unmarshal(payloadBytes, &payload); err != nil {
		fmt.Println("Invalid payload JSON")
		return
	}

	if payload.Role == "admin" && payload.User == "system_admin" {
		fmt.Println("Access Granted: Admin")
	} else {
		fmt.Println("Access Granted: User")
	}
}
EOF

    chmod -R 777 /home/user
