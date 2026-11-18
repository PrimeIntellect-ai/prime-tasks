#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    cat << 'EOF' > /app/legacy_hasher.cpp
#include <iostream>
#include <string>
#include <iomanip>

int main(int argc, char** argv) {
    if (argc < 2) return 1;
    std::string s = argv[1];
    unsigned int h = 0x55555555;
    for(char c : s) {
        h ^= (unsigned char)c;
        h = (h << 5) | (h >> 27);
        h += 0x12345678;
    }
    std::cout << std::hex << std::setfill('0') << std::setw(8) << h << std::endl;
    return 0;
}
EOF
    g++ -O3 /app/legacy_hasher.cpp -o /app/legacy_hasher
    strip /app/legacy_hasher
    rm /app/legacy_hasher.cpp

    cat << 'EOF' > /tmp/generate_data.py
import random
import string

def hash_pw(s):
    h = 0x55555555
    for c in s:
        h ^= ord(c)
        h = ((h << 5) & 0xFFFFFFFF) | (h >> 27)
        h = (h + 0x12345678) & 0xFFFFFFFF
    return f"{h:08x}"

random.seed(42)
words = []
for _ in range(100000):
    words.append(''.join(random.choices(string.ascii_lowercase, k=random.randint(5, 10))))

with open('/home/user/words.txt', 'w') as f:
    f.write('\n'.join(words) + '\n')

users = ['user' + str(i) for i in range(49999)] + ['admin']
random.shuffle(users)

dump = []
for u in users:
    w = random.choice(words)
    dump.append(f"{u}:{hash_pw(w)}")

with open('/home/user/dump.txt', 'w') as f:
    f.write('\n'.join(dump) + '\n')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    mkdir -p /home/user/.ssh
    chmod -R 777 /home/user
