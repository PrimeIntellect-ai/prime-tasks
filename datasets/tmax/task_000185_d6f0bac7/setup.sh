#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go binutils
    pip3 install pytest

    # Create directories
    mkdir -p /home/user/configs
    mkdir -p /app

    # Create backup rules
    cat << 'EOF' > /home/user/backup_rules.json
{"extension": ".conf", "max_age_days": 7, "min_size_bytes": 1024}
EOF

    # Generate dummy configuration files
    cat << 'EOF' > /tmp/gen_configs.py
import os
import time
import random

os.makedirs('/home/user/configs', exist_ok=True)
random.seed(42)

# Generate 100 files
for i in range(100):
    path = f"/home/user/configs/file_{i}.conf"
    with open(path, "wb") as f:
        data = bytearray()
        # Create data that compresses differently at flate default vs best
        for _ in range(800):
            key = f"config_key_{random.randint(1, 50)}".encode()
            val = f"{random.randint(1, 500)}".encode()
            data.extend(key + b"=" + val + b"\n")
        f.write(data)

    # Set mtime to 3 days ago (within the 7 days max_age)
    mtime = time.time() - (86400 * 3)
    os.utime(path, (mtime, mtime))

# Generate some files that should be ignored (wrong extension, too old, too small)
with open("/home/user/configs/ignore1.txt", "w") as f:
    f.write("wrong extension")

with open("/home/user/configs/ignore2.conf", "w") as f:
    f.write("too small")

path = "/home/user/configs/ignore3.conf"
with open(path, "w") as f:
    f.write("A" * 2000)
os.utime(path, (time.time() - (86400 * 10), time.time() - (86400 * 10))) # too old
EOF
    python3 /tmp/gen_configs.py

    # Create the config_unpacker Go program
    cat << 'EOF' > /tmp/config_unpacker.go
package main

import (
	"bytes"
	"compress/flate"
	"encoding/binary"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("Usage: config_unpacker <archive> <outdir>")
		os.Exit(1)
	}
	data, err := os.ReadFile(os.Args[1])
	if err != nil {
		panic(err)
	}
	outdir := os.Args[2]

	r := bytes.NewReader(data)
	var magic [4]byte
	if err := binary.Read(r, binary.LittleEndian, &magic); err != nil {
		panic(err)
	}
	if string(magic[:]) != "CFGP" {
		panic("Invalid magic bytes")
	}

	var numFiles uint32
	if err := binary.Read(r, binary.LittleEndian, &numFiles); err != nil {
		panic(err)
	}

	for i := uint32(0); i < numFiles; i++ {
		var pathLen uint16
		if err := binary.Read(r, binary.LittleEndian, &pathLen); err != nil {
			panic(err)
		}

		pathBuf := make([]byte, pathLen)
		if _, err := io.ReadFull(r, pathBuf); err != nil {
			panic(err)
		}
		path := string(pathBuf)

		var origSize, compSize uint32
		if err := binary.Read(r, binary.LittleEndian, &origSize); err != nil {
			panic(err)
		}
		if err := binary.Read(r, binary.LittleEndian, &compSize); err != nil {
			panic(err)
		}

		compData := make([]byte, compSize)
		if _, err := io.ReadFull(r, compData); err != nil {
			panic(err)
		}

		fr := flate.NewReader(bytes.NewReader(compData))
		decompData, err := io.ReadAll(fr)
		if err != nil {
			panic(err)
		}
		fr.Close()

		if uint32(len(decompData)) != origSize {
			panic("Uncompressed size mismatch")
		}

		outPath := filepath.Join(outdir, path)
		if err := os.MkdirAll(filepath.Dir(outPath), 0755); err != nil {
			panic(err)
		}
		if err := os.WriteFile(outPath, decompData, 0644); err != nil {
			panic(err)
		}
	}
}
EOF

    # Compile and strip the unpacker
    cd /tmp
    go build -ldflags="-s -w" -o /app/config_unpacker config_unpacker.go
    strip /app/config_unpacker
    chmod +x /app/config_unpacker

    # Clean up
    rm /tmp/gen_configs.py /tmp/config_unpacker.go

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
