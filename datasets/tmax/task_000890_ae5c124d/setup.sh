#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc git
pip3 install pytest

# Create legacy C binary
mkdir -p /app
cat << 'EOF' > /app/legacy_encoder.c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    char *input = argv[1];
    char *key = "SUPPORT";
    int key_len = strlen(key);
    for (int i = 0; i < strlen(input); i++) {
        unsigned char c = input[i];
        unsigned char k = key[i % key_len];
        unsigned char res = (c ^ k) + 5;
        printf("%02x", res);
    }
    printf("\n");
    return 0;
}
EOF
gcc -o /app/legacy_encoder /app/legacy_encoder.c
rm /app/legacy_encoder.c

useradd -m -s /bin/bash user || true

# Create git repo
mkdir -p /home/user/encoder_repo
cd /home/user/encoder_repo
git init
git config user.email "dev@example.com"
git config user.name "Dev"

cat << 'EOF' > encode.py
import sys

def encode(input_str):
    key = "SUPPORT"
    res = []
    for i, c in enumerate(input_str):
        k = key[i % len(key)]
        val = (ord(c) ^ ord(k)) + 5
        res.append(f"{val:02x}")
    return "".join(res)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    print(encode(sys.argv[1]))
EOF

git add encode.py
git commit -m "Initial commit: working Python encoder"
git tag v1.0

# Create intermediate dummy commits
for i in $(seq 1 3); do
    echo "# dummy $i" >> encode.py
    git commit -am "Refactor: minor cleanup $i"
done

# Create the bad commit
cat << 'EOF' > encode.py
import sys

def encode(input_str):
    key = "SUPPORT"
    res = []
    for i, c in enumerate(input_str):
        if c == '!' or c == '~':
            _ = 1 / 0
        k = key[i % (len(key) - 1)]
        val = (ord(c) ^ ord(k)) + 5
        res.append(f"{val:02x}")
    return "".join(res)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(1)
    print(encode(sys.argv[1]))
EOF

git commit -am "Optimize key cycling"

# Create more dummy commits
for i in $(seq 4 6); do
    echo "# dummy $i" >> encode.py
    git commit -am "Refactor: minor cleanup $i"
done

chmod -R 777 /home/user
