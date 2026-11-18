#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc tshark tcpdump
    pip3 install pytest scapy

    useradd -m -s /bin/bash user || true

    python3 - << 'EOF'
import os
import subprocess

work_dir = "/home/user/telemetry_diag"
os.makedirs(work_dir, exist_ok=True)

# 1. Create the C code for legacy_decoder and compile it
c_code = """
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    if(argc != 2) {
        printf("Usage: ./legacy_decoder <hex_string>\\n");
        return 1;
    }
    // Simple reverse engineering logic: parse hex, XOR with 0x5A5A, modulo 5000
    long raw_val = strtol(argv[1], NULL, 16);
    int decoded = (raw_val ^ 0x5A5A) % 5000;
    printf("%d\\n", decoded);
    return 0;
}
"""
c_path = os.path.join(work_dir, "decoder.c")
with open(c_path, "w") as f:
    f.write(c_code)

bin_path = os.path.join(work_dir, "legacy_decoder")
subprocess.run(["gcc", c_path, "-o", bin_path, "-s"]) # -s to strip
os.remove(c_path)

# 2. Generate traffic.pcap using scapy
setup_pcap = f"""
from scapy.all import *
packets = [
    IP(dst="192.168.1.100")/UDP(dport=8888)/Raw(load=bytes.fromhex("1A2B")),
    IP(dst="192.168.1.100")/UDP(dport=8888)/Raw(load=bytes.fromhex("5F5F")),
    IP(dst="192.168.1.100")/UDP(dport=8888)/Raw(load=bytes.fromhex("0000")),
    IP(dst="192.168.1.100")/UDP(dport=8080)/Raw(load=bytes.fromhex("FFFF")), # Ignore, wrong port
    IP(dst="192.168.1.100")/UDP(dport=8888)/Raw(load=bytes.fromhex("ABCD"))
]
wrpcap("{work_dir}/traffic.pcap", packets)
"""
subprocess.run(["python3", "-c", setup_pcap])

# 3. Create pipeline.py with buggy formula and missing decoder
pipeline_code = """
import subprocess

def decode_payload(hex_str: str) -> int:
    # TODO: Implement the logic of legacy_decoder here in pure Python.
    # Currently it just calls the binary.
    result = subprocess.run(['./legacy_decoder', hex_str], capture_output=True, text=True)
    return int(result.stdout.strip())

def calculate_temperature(raw_val: int) -> float:
    # BUGGY FORMULA: Supposed to convert to F, but currently does a naive multiplier
    # Fix this based on datasheet.txt
    temp = raw_val * 1.5 + 10
    return round(temp, 2)
"""
with open(os.path.join(work_dir, "pipeline.py"), "w") as f:
    f.write(pipeline_code.strip() + "\n")

# 4. Create datasheet.txt
datasheet_content = """
SENSOR MODEL: TX-9000
METRIC CONVERSION SPECIFICATION

The raw decoded integer represents temperature in Celsius scaled by a factor of 10.
To convert the raw integer to Fahrenheit, follow this physical formula:
1. Divide the raw integer by 10.0 to get Celsius.
2. Multiply by 1.8 (or 9/5).
3. Add 32.0.
"""
with open(os.path.join(work_dir, "datasheet.txt"), "w") as f:
    f.write(datasheet_content.strip() + "\n")
EOF

    chmod -R 777 /home/user
