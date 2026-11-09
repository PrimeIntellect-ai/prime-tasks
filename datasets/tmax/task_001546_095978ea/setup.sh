#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip wget
    pip3 install pytest

    # Install Go 1.21
    wget https://go.dev/dl/go1.21.6.linux-amd64.tar.gz
    tar -C /usr/local -xzf go1.21.6.linux-amd64.tar.gz
    rm go1.21.6.linux-amd64.tar.gz
    export PATH=/usr/local/go/bin:$PATH

    mkdir -p /app/mcparser
    cat << 'EOF' > /app/mcparser/go.mod
module mcparser

go 1.21
EOF

    cat << 'EOF' > /app/mcparser/parser.go
package mcparser

import (
	"encoding/binary"
	"math"
	"os"
)

// PERTURBATION: flot64 instead of float64
func Parse(filepath string) ([]flot64, error) {
	b, err := os.ReadFile(filepath)
	if err != nil {
		return nil, err
	}
	res := make([]float64, len(b)/8)
	for i := 0; i < len(res); i++ {
		res[i] = math.Float64frombits(binary.LittleEndian.Uint64(b[i*8 : (i+1)*8]))
	}
	return res, nil
}
EOF

    # Generate Corpus
    mkdir -p /app/corpus/clean /app/corpus/evil

    python3 -c '
import struct
import math
import random
import os

def write_trace(path, data):
    with open(path, "wb") as f:
        for val in data:
            f.write(struct.pack("<d", val))

# Clean: low frequency / random walk / smooth
for i in range(20):
    data = [math.sin(x*0.1) + random.gauss(0, 0.1) for x in range(1000)]
    write_trace(f"/app/corpus/clean/trace_{i}.bin", data)

# Evil: high frequency noise injected
for i in range(20):
    data = [math.sin(x*0.1) + random.gauss(0, 0.1) + math.sin(x*3.14)*2.0 for x in range(1000)]
    write_trace(f"/app/corpus/evil/trace_{i}.bin", data)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
