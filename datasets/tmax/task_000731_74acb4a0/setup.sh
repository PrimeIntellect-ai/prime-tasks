#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/legacy_project
    cd /home/user/legacy_project

    cat << 'EOF' > lib_calc.c
#include <stdint.h>
uint32_t compute_checksum(const char* data, int length) {
    uint32_t sum = 0;
    for(int i=0; i<length; i++) {
        sum = (sum << 1) ^ (data[i] * 31);
    }
    return sum;
}
EOF

    cat << 'EOF' > checksum.py
import ctypes
from vm import MAGIC_CONSTANT

lib = ctypes.CDLL('./lib_calc.so')
lib.compute_checksum.argtypes = [ctypes.c_char_p, ctypes.c_int]
lib.compute_checksum.restype = ctypes.c_uint32

def get_checksum(data_str):
    # Py2 to Py3 bug: data_str needs encoding to bytes
    res = lib.compute_checksum(data_str, len(data_str))
    return res + MAGIC_CONSTANT
EOF

    cat << 'EOF' > vm.py
import checksum

MAGIC_CONSTANT = 10

class VM:
    def __init__(self):
        self.memory = ""

    def execute(self, instructions):
        for line in instructions:
            parts = line.strip().split(" ", 1)
            if parts[0] == "LOAD":
                self.memory = parts[1]
            elif parts[0] == "CHECKSUM":
                val = checksum.get_checksum(self.memory)
                return val
EOF

    cat << 'EOF' > main.py
from vm import VM

def main():
    with open("input.txt", "r") as f:
        lines = f.readlines()

    machine = VM()
    result = machine.execute(lines)
    with open("output.txt", "w") as f:
        f.write(str(result) + "\n")

if __name__ == "__main__":
    main()
EOF

    cat << 'EOF' > input.txt
LOAD AB
CHECKSUM
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/legacy_project
    chmod -R 777 /home/user
