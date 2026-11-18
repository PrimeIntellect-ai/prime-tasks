#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssl gcc binutils cargo curl
    pip3 install pytest

    mkdir -p /app

    # Generate rogue cert and get fingerprint
    openssl req -x509 -newkey rsa:2048 -keyout /app/rogue_cert.key -out /app/rogue_cert.pem -days 365 -nodes -subj "/CN=rogue"
    export FINGERPRINT=$(openssl x509 -in /app/rogue_cert.pem -outform DER | sha256sum | awk '{print $1}')

    # Create payload_decoder.c
    cat << 'EOF' > /app/payload_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int b64[256] = {
    ['A']=0, ['B']=1, ['C']=2, ['D']=3, ['E']=4, ['F']=5, ['G']=6, ['H']=7,
    ['I']=8, ['J']=9, ['K']=10, ['L']=11, ['M']=12, ['N']=13, ['O']=14, ['P']=15,
    ['Q']=16, ['R']=17, ['S']=18, ['T']=19, ['U']=20, ['V']=21, ['W']=22, ['X']=23,
    ['Y']=24, ['Z']=25, ['a']=26, ['b']=27, ['c']=28, ['d']=29, ['e']=30, ['f']=31,
    ['g']=32, ['h']=33, ['i']=34, ['j']=35, ['k']=36, ['l']=37, ['m']=38, ['n']=39,
    ['o']=40, ['p']=41, ['q']=42, ['r']=43, ['s']=44, ['t']=45, ['u']=46, ['v']=47,
    ['w']=48, ['x']=49, ['y']=50, ['z']=51, ['0']=52, ['1']=53, ['2']=54, ['3']=55,
    ['4']=56, ['5']=57, ['6']=58, ['7']=59, ['8']=60, ['9']=61, ['+']=62, ['/']=63
};

int main() {
    char in[8192];
    size_t len = fread(in, 1, sizeof(in), stdin);
    int val = 0, valb = -8;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = in[i];
        if (c == '=' || c == '\n' || c == '\r') continue;
        if (b64[c] == 0 && c != 'A') continue;
        val = (val << 6) + b64[c];
        valb += 6;
        if (valb >= 0) {
            putchar(((val >> valb) & 0xFF) ^ 0x5A);
            valb -= 8;
        }
    }
    return 0;
}
EOF

    gcc -O2 /app/payload_decoder.c -o /app/payload_decoder
    strip -s /app/payload_decoder
    rm /app/payload_decoder.c

    # Generate corpora
    cat << 'EOF' > /app/generate_data.py
import os
import json
import base64

FINGERPRINT = os.environ['FINGERPRINT']

def encode_payload(text):
    xored = bytes([b ^ 0x5A for b in text.encode('utf-8')])
    return base64.b64encode(xored).decode('utf-8')

def make_json(is_evil, idx):
    if is_evil:
        text = f"EXEC_C2: {FINGERPRINT} do_bad_stuff_{idx}"
    else:
        text = f"Just some benign text {idx}"

    return {
        "timestamp": "2023-10-25T12:00:00Z",
        "metadata": { "source_ip": f"192.168.1.{idx%255}" },
        "data_payload": encode_payload(text)
    }

os.makedirs('/app/training_data', exist_ok=True)
os.makedirs('/app/evaluation_corpus/evil', exist_ok=True)
os.makedirs('/app/evaluation_corpus/clean', exist_ok=True)

for i in range(3):
    with open(f'/app/training_data/clean_{i}.json', 'w') as f:
        json.dump(make_json(False, i), f)
for i in range(2):
    with open(f'/app/training_data/evil_{i}.json', 'w') as f:
        json.dump(make_json(True, i), f)

for i in range(50):
    with open(f'/app/evaluation_corpus/clean/{i}.json', 'w') as f:
        json.dump(make_json(False, i), f)
    with open(f'/app/evaluation_corpus/evil/{i}.json', 'w') as f:
        json.dump(make_json(True, i), f)
EOF

    python3 /app/generate_data.py
    rm /app/generate_data.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
