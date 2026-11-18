#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev
    pip3 install pytest

    cat << 'EOF' > /tmp/setup.py
import os
import subprocess

os.makedirs("/home/user", exist_ok=True)

password = b"B@ckd00r_99!\x00\x00\x00\x00"
xor_key = 0x5A
obfuscated = bytes([b ^ xor_key for b in password])

hex_array = ", ".join(hex(b) for b in obfuscated)

cpp_code = """
#include <iostream>
#include <cstring>

const unsigned char secret[] = { """ + hex_array + """ };

bool check_auth(const char* input) {
    char dec[17];
    for(int i=0; i<16; ++i) dec[i] = secret[i] ^ 0x5A;
    dec[16] = 0;
    return strcmp(input, dec) == 0;
}

int main(int argc, char** argv) {
    if(argc > 1 && check_auth(argv[1])) std::cout << "Access Granted\\n";
    else std::cout << "Access Denied\\n";
    return 0;
}
"""

with open("/home/user/legacy_auth.cpp", "w") as f:
    f.write(cpp_code)

subprocess.run(["g++", "-O2", "/home/user/legacy_auth.cpp", "-o", "/home/user/legacy_auth", "-s"], check=True)
os.remove("/home/user/legacy_auth.cpp")

records = [
    ("10.0.0.5", b"wrongpass\x00\x00\x00\x00\x00\x00\x00", 0),
    ("192.168.1.100", b"B@ckd00r_99!\x00\x00\x00\x00", 1),
    ("172.16.0.4", b"B@ckd00r_99!\x00\x00\x00\x00", 0),
    ("10.50.2.1", b"admin123\x00\x00\x00\x00\x00\x00\x00\x00", 0),
    ("8.8.8.8", b"B@ckd00r_99!\x00\x00\x00\x00", 1)
]

with open("/home/user/traffic.bin", "wb") as f:
    for ip, pwd, success in records:
        ip_bytes = bytes(map(int, ip.split('.')))
        f.write(ip_bytes)
        f.write(pwd[:16])
        f.write(bytes([success]))

new_pass = "SuperSecureR0tat10n!2024"
with open("/home/user/new_password.txt", "w") as f:
    f.write(new_pass)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
