#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/gowaf

    cat << 'EOF' > /app/gowaf/go.mod
module github.com/testorg/gowaf

go 1.20
EOF

    cat << 'EOF' > /app/gowaf/parser.go
package gowaf

import (
	"net/url"
)

func NormalizePayload(input string) string {
	decoded, err := url.QueryUnescape(input)
	if err != nil {
		decoded = input
	}
	decoded = strings.ToLower(decoded)
	return strings.ReplaceAll(decoded, "\x00", "")
}
EOF

    cat << 'EOF' > /app/gowaf/Makefile
build:
	go biuld ./...
EOF

    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/corpus/clean

    cat << 'EOF' > /home/user/legacy_waf.py
import sys
import urllib.parse

def normalize(payload):
    payload = urllib.parse.unquote(payload)
    return payload.lower().replace('\x00', '')

def is_evil(payload):
    norm = normalize(payload)
    if "<script>" in norm or "javascript:" in norm:
        return True
    if "union select" in norm or "drop table" in norm:
        return True
    if "../" in norm or "/etc/passwd" in norm:
        return True
    return False

# Pseudo-code translation target.
EOF

    echo -n '%3Cscript%3Ealert(1)%3C%2Fscript%3E' > /home/user/corpus/evil/1.txt
    echo -n 'UNION%20SELECT%20*%20FROM%20users' > /home/user/corpus/evil/2.txt
    echo -n '..%2F..%2F..%2Fetc%2Fpasswd' > /home/user/corpus/evil/3.txt

    echo -n 'hello world' > /home/user/corpus/clean/1.txt
    echo -n 'username=john&password=123' > /home/user/corpus/clean/2.txt
    echo -n 'search=apple%20pie' > /home/user/corpus/clean/3.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
