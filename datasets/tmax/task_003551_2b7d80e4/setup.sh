#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        tesseract-ocr \
        binutils \
        libpcap-dev

    pip3 install pytest scapy Pillow

    mkdir -p /app

    # Generate intercepted_key.png
    cat << 'EOF' > /tmp/gen_image.py
from PIL import Image, ImageDraw, ImageFont
img = Image.new('RGB', (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
# Using default font, drawing text
d.text((10, 40), "Key: K3yM4st3r2024XOR", fill=(0, 0, 0))
img.save('/app/intercepted_key.png')
EOF
    python3 /tmp/gen_image.py

    # Generate auth_client ELF binary
    cat << 'EOF' > /tmp/client.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

void xor_encrypt(const char* input, char* output, int len, const char* key) {
    int key_len = strlen(key);
    for(int i=0; i<len; i++) {
        output[i] = input[i] ^ key[i % key_len];
    }
}

int main(int argc, char** argv) {
    if(argc != 3) return 1;
    const char* user = argv[1];
    const char* token = argv[2];
    const char* key = "K3yM4st3r2024XOR";

    uint16_t u_len = strlen(user);
    uint16_t t_len = strlen(token);

    char* enc_u = malloc(u_len);
    char* enc_t = malloc(t_len);

    xor_encrypt(user, enc_u, u_len, key);
    xor_encrypt(token, enc_t, t_len, key);

    fwrite(&u_len, 1, 2, stdout);
    fwrite(enc_u, 1, u_len, stdout);
    fwrite(&t_len, 1, 2, stdout);
    fwrite(enc_t, 1, t_len, stdout);

    free(enc_u);
    free(enc_t);
    return 0;
}
EOF
    gcc -O2 -o /app/auth_client /tmp/client.c
    strip /app/auth_client

    # Generate pcaps and ground truth
    cat << 'EOF' > /tmp/gen_pcaps.py
import json
import random
import string
import struct
from scapy.all import wrpcap, Ether, IP, TCP, Raw

KEY = b"K3yM4st3r2024XOR"

def xor_crypt(data: bytes, key: bytes) -> bytes:
    return bytes([b ^ key[i % len(key)] for i, b in enumerate(data)])

def make_payload(user: str, token: str) -> bytes:
    u_bytes = user.encode()
    t_bytes = token.encode()
    enc_u = xor_crypt(u_bytes, KEY)
    enc_t = xor_crypt(t_bytes, KEY)
    # Little-endian 16-bit lengths
    return struct.pack("<H", len(u_bytes)) + enc_u + struct.pack("<H", len(t_bytes)) + enc_t

def random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_pcap(filename, num_valid, is_eval=False):
    packets = []
    ground_truth = []

    total_packets = num_valid * 2
    valid_indices = random.sample(range(1, total_packets + 1), num_valid)
    valid_indices.sort()
    valid_set = set(valid_indices)

    for i in range(1, total_packets + 1):
        if i in valid_set:
            user = random_string(random.randint(5, 10))
            token = random_string(random.randint(10, 20))
            payload = make_payload(user, token)
            pkt = Ether()/IP(src="192.168.1.100", dst="192.168.1.50")/TCP(sport=random.randint(1024, 65535), dport=9090)/Raw(load=payload)
            packets.append(pkt)
            if is_eval:
                ground_truth.append({
                    "packet_index": i,
                    "username": user,
                    "token": token
                })
        else:
            # Background traffic
            pkt = Ether()/IP(src="192.168.1.100", dst="8.8.8.8")/TCP(sport=random.randint(1024, 65535), dport=80)/Raw(load=b"GET / HTTP/1.1\r\n\r\n")
            packets.append(pkt)

    wrpcap(filename, packets)
    if is_eval:
        with open("/app/eval_ground_truth.json", "w") as f:
            json.dump(ground_truth, f)

# Set seeds for reproducibility
random.seed(42)
generate_pcap("/app/traffic.pcap", 50, is_eval=False)
generate_pcap("/app/eval.pcap", 10000, is_eval=True)
EOF
    python3 /tmp/gen_pcaps.py

    # Cleanup temp files
    rm -f /tmp/gen_image.py /tmp/client.c /tmp/gen_pcaps.py

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
