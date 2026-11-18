#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app
mkdir -p /home/user/.ssh

cat << 'EOF' > /home/user/.ssh/authorized_keys
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... legitimate@corp.com
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... hacker@pwned
EOF

cat << 'EOF' > /home/user/app/server.go
package main

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"strings"
)

type Header struct {
	Alg string `json:"alg"`
	Typ string `json:"typ"`
}

func VerifyToken(tokenString string, secret string) (map[string]interface{}, error) {
	parts := strings.Split(tokenString, ".")
	if len(parts) != 3 {
		return nil, errors.New("invalid token format")
	}

	headerBytes, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return nil, err
	}

	var header Header
	if err := json.Unmarshal(headerBytes, &header); err != nil {
		return nil, err
	}

	// Vulnerable logic
	if header.Alg == "none" {
		payloadBytes, _ := base64.RawURLEncoding.DecodeString(parts[1])
		var payload map[string]interface{}
		json.Unmarshal(payloadBytes, &payload)
		return payload, nil
	}

	// Normal verification would go here (omitted for brevity)
	if header.Alg != "HS256" {
		return nil, errors.New("unsupported algorithm")
	}

	return nil, errors.New("signature verification failed")
}
EOF

chmod -R 777 /home/user
chmod 700 /home/user/.ssh
chmod 600 /home/user/.ssh/authorized_keys
