#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip golang
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/parser.go
package main

import (
	"encoding/binary"
	"os"
)

func parseData(data []byte) string {
	if len(data) < 6 {
		return ""
	}
	magic := string(data[0:2])
	if magic != "GO" {
		return ""
	}
	length := binary.BigEndian.Uint32(data[2:6])

	// BUG: off by one. Tries to read 1 extra byte, causing a panic if the buffer ends exactly here
	payload := data[6 : 6+length+1]

	return string(payload)
}

func main() {
	if len(os.Args) < 2 {
		return
	}

	// BUG: os.Readfile instead of os.ReadFile
	data, err := os.Readfile(os.Args[1])
	if err != nil {
		return
	}

	result := parseData(data)
	if result != "" {
		// Outputting to stdout originally, agent needs to change to file
		os.Stdout.WriteString(result)
	}
}
EOF

python3 -c 'open("/home/user/payload.bin", "wb").write(b"\x47\x4f\x00\x00\x00\x08\x43\x52\x49\x54\x49\x43\x41\x4c")'

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
