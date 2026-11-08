#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /app/legacy_bytecode_gen
#!/usr/bin/env python3
import sys
import struct

def generate_bytecode(seed):
    # Deterministic generation
    instructions = []
    instructions.append((0x01, seed % 256, 0)) # LOAD_CONST (seed % 256) into reg 0
    instructions.append((0x01, 1, 1))          # LOAD_CONST 1 into reg 1

    # Loop to do some math
    for i in range(5):
        instructions.append((0x02, 0, 1))      # ADD reg 0 to reg 1
        instructions.append((0x04, (seed + i) % 256, 0)) # XOR_CONST to reg 0
        instructions.append((0x03, 0, 1))      # MUL reg 0 to reg 1

    instructions.append((0xFF, 0, 0))          # RETURN

    with open("output.bin", "wb") as f:
        for op, arg1, arg2 in instructions:
            f.write(struct.pack("BBB", op, arg1, arg2))

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_bytecode(int(sys.argv[1]))
EOF
    chmod +x /app/legacy_bytecode_gen

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
