#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/hidden_corpus/clean /app/hidden_corpus/evil

    cat << 'EOF' > /tmp/wal_ingester.go
package main
import ("encoding/binary"; "fmt"; "io"; "os")
func main() {
	if len(os.Args) < 2 { return }
	f, err := os.Open(os.Args[1])
	if err != nil { return }
	defer f.Close()
	for {
		var typ uint8
		if err := binary.Read(f, binary.LittleEndian, &typ); err != nil { break }
		var length uint16
		if err := binary.Read(f, binary.LittleEndian, &length); err != nil { break }
		fmt.Printf("Processing type %d...\n", typ)
		if typ == 0xFF && length == 13 { select {} }
		payload := make([]byte, length)
		if _, err := io.ReadFull(f, payload); err != nil { break }
	}
}
EOF
    go build -ldflags="-s -w" -o /app/wal_ingester /tmp/wal_ingester.go

    cat << 'EOF' > /tmp/generate_corpus.py
import os
import random
import struct

def generate_file(path, is_evil):
    with open(path, 'wb') as f:
        num_entries = random.randint(5, 15)
        evil_idx = random.randint(0, num_entries - 1) if is_evil else -1
        for i in range(num_entries):
            if i == evil_idx:
                f.write(struct.pack('<BH', 0xFF, 13))
                f.write(os.urandom(13))
            else:
                typ = random.randint(0, 0xFE)
                length = random.randint(1, 50)
                if length == 13 and typ == 0xFF:
                    typ = 0x00
                f.write(struct.pack('<BH', typ, length))
                f.write(os.urandom(length))

for i in range(20):
    generate_file(f'/app/corpus/clean/clean_{i}.wal', False)
    generate_file(f'/app/corpus/evil/evil_{i}.wal', True)

for i in range(50):
    generate_file(f'/app/hidden_corpus/clean/clean_{i}.wal', False)
    generate_file(f'/app/hidden_corpus/evil/evil_{i}.wal', True)
EOF
    python3 /tmp/generate_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
