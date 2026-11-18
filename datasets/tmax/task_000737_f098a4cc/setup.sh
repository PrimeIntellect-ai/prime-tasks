#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb strace ltrace binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    cat << 'EOF' > /tmp/setup.py
import os

encoder_c = """
#include <stdio.h>
#include <string.h>

int main() {
    int c;
    while ((c = getchar()) != EOF) {
        if (c == '\\n') continue;
        printf("%02X", (unsigned char)(c ^ 0x42));
    }
    printf("\\n");
    return 0;
}
"""

with open("/tmp/encoder.c", "w") as f:
    f.write(encoder_c)

os.system("gcc /tmp/encoder.c -o /app/custom_encoder")
os.system("strip /app/custom_encoder")

def encode(text):
    return "".join(f"{ord(c) ^ 0x42:02X}" for c in text)

clean_samples = [
    "username=john&status=active",
    "page=about",
    "id=12345"
]

evil_samples = [
    "username=admin' OR 1=1--",
    "<script>alert(1)</script>",
    "UNION SELECT password FROM users",
    "id=1; DROP TABLE users",
    "javascript:alert(1)"
]

for i, sample in enumerate(clean_samples):
    with open(f"/app/corpus/clean/sample_{i}.txt", "w") as f:
        f.write(encode(sample))

for i, sample in enumerate(evil_samples):
    with open(f"/app/corpus/evil/sample_{i}.txt", "w") as f:
        f.write(encode(sample))
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py /tmp/encoder.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
