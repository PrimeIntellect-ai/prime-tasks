#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go openssh-client
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /app/decoder.go
package main
import (
	"encoding/base64"
	"fmt"
	"os"
)
func main() {
	if len(os.Args) < 2 {
		return
	}
	data, err := base64.StdEncoding.DecodeString(os.Args[1])
	if err != nil {
		fmt.Print(os.Args[1])
		return
	}
	for i := range data {
		data[i] ^= 0x5A
	}
	fmt.Print(string(data))
}
EOF
    go build -ldflags="-s -w" -o /app/decoder /app/decoder.go
    chmod +x /app/decoder

    cat << 'EOF' > /tmp/gen.py
import os
import subprocess
import base64

def encode(s):
    return base64.b64encode(bytes([ord(c) ^ 0x5A for c in s])).decode()

# Clean 1
subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", "/app/corpus/clean/clean1", "-N", "", "-C", "user@host"])
os.chmod("/app/corpus/clean/clean1.pub", 0o600)

# Clean 2
c2 = encode("NORMAL")
subprocess.run(["ssh-keygen", "-t", "rsa", "-b", "2048", "-f", "/app/corpus/clean/clean2", "-N", "", "-C", c2])
os.chmod("/app/corpus/clean/clean2.pub", 0o600)

# Evil 1
subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", "/app/corpus/evil/evil1", "-N", "", "-C", "evil1"])
os.chmod("/app/corpus/evil/evil1.pub", 0o644)

# Evil 2
subprocess.run(["ssh-keygen", "-t", "dsa", "-f", "/app/corpus/evil/evil2", "-N", "", "-C", "evil2"])
os.chmod("/app/corpus/evil/evil2.pub", 0o600)

# Evil 3
subprocess.run(["ssh-keygen", "-t", "rsa", "-b", "1024", "-f", "/app/corpus/evil/evil3", "-N", "", "-C", "evil3"])
os.chmod("/app/corpus/evil/evil3.pub", 0o600)

# Evil 4
c4 = encode("SUPER_EVIL_PAYLOAD")
subprocess.run(["ssh-keygen", "-t", "ed25519", "-f", "/app/corpus/evil/evil4", "-N", "", "-C", c4])
os.chmod("/app/corpus/evil/evil4.pub", 0o600)
EOF
    python3 /tmp/gen.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
