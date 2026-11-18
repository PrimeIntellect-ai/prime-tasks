#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/reader.go
package main

import (
	"encoding/binary"
	"fmt"
	"math"
	"os"
)

func main() {
	data, err := os.ReadFile("/home/user/telemetry.bin")
	if err != nil {
		panic(err)
	}

	if string(data[:4]) != "TELE" {
		panic("invalid magic header")
	}

	offset := 4
	for offset+16 <= len(data) {
		id := binary.LittleEndian.Uint32(data[offset : offset+4])
		valBits := binary.LittleEndian.Uint64(data[offset+4 : offset+12])
		val := math.Float64frombits(valBits)
		marker := binary.LittleEndian.Uint32(data[offset+12 : offset+16])

		if marker != 0xAABBCCDD {
			panic(fmt.Sprintf("corruption detected at offset %d: expected marker 0xAABBCCDD, got 0x%X", offset, marker))
		}

		fmt.Printf("%d,%.4f\n", id, val)
		offset += 16
	}
}
EOF

    cat << 'EOF' > /tmp/gen_bin.py
import struct

with open('/home/user/telemetry.bin', 'wb') as f:
    # Header
    f.write(b'TELE')

    # Record 1: ID=1, Value=10.5 (float64)
    f.write(struct.pack('<I', 1))
    f.write(struct.pack('<d', 10.5))
    f.write(struct.pack('<I', 0xAABBCCDD))

    # Record 2: ID=2, Value=20.25 (float32 padded with 0xFFFFFFFF)
    f.write(struct.pack('<I', 2))
    f.write(struct.pack('<f', 20.25))
    f.write(b'\xff\xff\xff\xff')
    f.write(struct.pack('<I', 0xAABBCCDD))

    # Garbage bytes
    f.write(b'\x12\x34\x56\x78\x90')

    # Record 3: ID=3, Value=30.125 (float64)
    f.write(struct.pack('<I', 3))
    f.write(struct.pack('<d', 30.125))
    f.write(struct.pack('<I', 0xAABBCCDD))

    # Record 4: ID=4, Value=40.875 (float32 padded with 0xFFFFFFFF)
    f.write(struct.pack('<I', 4))
    f.write(struct.pack('<f', 40.875))
    f.write(b'\xff\xff\xff\xff')
    f.write(struct.pack('<I', 0xAABBCCDD))

EOF

    python3 /tmp/gen_bin.py
    rm /tmp/gen_bin.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
