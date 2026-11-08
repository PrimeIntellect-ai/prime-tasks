#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install necessary packages for building C code, generating audio, and Rust
apt-get install -y gcc build-essential espeak rustc cargo curl

# Create /app directory
mkdir -p /app

# Create and compile the C2 obfuscator
cat << 'EOF' > /tmp/obfuscator.c
#include <stdio.h>
int main() {
    int c;
    int counter = 0;
    while ((c = fgetc(stdin)) != EOF) {
        // Simple byte obfuscation: XOR with 0x42, then add the byte's index modulo 8
        int out = (c ^ 0x42) + (counter % 8);
        fputc(out & 0xFF, stdout);
        counter++;
    }
    return 0;
}
EOF
gcc -O2 -s /tmp/obfuscator.c -o /app/c2_obfuscator
rm /tmp/obfuscator.c

# Generate the intercepted audio file
espeak -w /app/intercepted.wav "Fallback C2 server is at one nine two dot one six eight dot four five dot nine nine, port eight zero eight zero."

# Create user and set permissions
useradd -m -s /bin/bash user || true
chmod -R 777 /app
chmod -R 777 /home/user
