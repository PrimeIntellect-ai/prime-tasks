#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/builder.go
package main

import (
	"os"
	"strings"
	"time"
)

func main() {
	if len(os.Args) < 3 {
		os.Exit(1)
	}
	inDir := os.Args[1]
	outFile := os.Args[2]

	time.Sleep(1500 * time.Millisecond)

	tz := os.Getenv("TZ")
	lc := os.Getenv("LC_ALL")

	configPath := inDir + "/etc/ssh/sshd_config"
	content, err := os.ReadFile(configPath)

	valid := false
	if err == nil {
		if strings.Contains(string(content), "PubkeyAuthentication yes") && tz == "UTC" && lc == "C" {
			valid = true
		}
	}

	outStr := "QCOW2_MAGIC_CORRUPT\n"
	if valid {
		outStr = "QCOW2_MAGIC_VALID_REPRODUCIBLE\n"
	}

	os.WriteFile(outFile, []byte(outStr), 0644)
}
EOF
    cd /app
    go build -ldflags="-s -w" -o img_builder builder.go
    rm builder.go

    mkdir -p /home/user/backups /home/user/images
    for i in $(seq 1 10); do
        mkdir -p "/home/user/backups/node_${i}/etc/ssh"
        echo "Port 22" > "/home/user/backups/node_${i}/etc/ssh/sshd_config"
        echo "PubkeyAuthentication no" >> "/home/user/backups/node_${i}/etc/ssh/sshd_config"
    done

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
