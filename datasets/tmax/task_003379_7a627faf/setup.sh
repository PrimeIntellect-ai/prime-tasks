#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go curl wget
    pip3 install --default-timeout=100 pytest

    mkdir -p /app/pii-masker
    cat << 'EOF' > /app/pii-masker/go.mod
module example.com/pii-masker

go 1.20
EOF

    cat << 'EOF' > /app/pii-masker/masker.go
package piimasker

import (
	"regexp"
)

var emailRegex = regexp.MustCompile(`[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}`)

// MaskText redacts PII from the given string.
func MaskText(content string) string {
	emails := emailRegex.FindAllString(content, -1)
	for _, email := range emails {
		content = strings.ReplaceAll(content, email, "[REDACTED_EMAIL]")
	}
	return content
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
