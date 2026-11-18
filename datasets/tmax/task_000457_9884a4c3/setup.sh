#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils rustc cargo
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Create C source for api_oracle
    cat << 'EOF' > /app/api_oracle.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *token = argv[1];
    if (strncmp(token, "SEC_", 4) != 0) return 1;

    int xor_sum = 0;
    for (int i = 0; token[i] != '\0'; i++) {
        xor_sum ^= token[i];
    }

    if (xor_sum == 0x7F) {
        return 0;
    }
    return 1;
}
EOF

    # Compile and strip
    gcc -O2 -s /app/api_oracle.c -o /app/api_oracle
    strip --strip-all /app/api_oracle
    chmod 0755 /app/api_oracle
    rm /app/api_oracle.c

    # Generate tokens
    cat << 'EOF' > /tmp/gen_tokens.py
import random
import string

def generate_valid_token():
    while True:
        length = random.randint(10, 20)
        suffix = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        token = "SEC_" + suffix
        xor_sum = 0
        for char in token:
            xor_sum ^= ord(char)
        if xor_sum == 0x7F:
            return token

def generate_invalid_token():
    while True:
        length = random.randint(10, 20)
        token = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
        if not token.startswith("SEC_"):
            return token

tokens = []
for _ in range(105):
    tokens.append(generate_valid_token())

for _ in range(1000000 - 105):
    tokens.append(generate_invalid_token())

random.shuffle(tokens)

with open("/home/user/tokens.txt", "w") as f:
    for t in tokens:
        f.write(t + "\n")
EOF

    python3 /tmp/gen_tokens.py
    rm /tmp/gen_tokens.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
