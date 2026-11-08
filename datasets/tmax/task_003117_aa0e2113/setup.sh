#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil /app/corpus/holdout_clean /app/corpus/holdout_evil

    # Create the legacy decoder C source
    cat << 'EOF' > /app/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int b64_inv(char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return -1;
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    char *pass = argv[1];
    int pass_len = strlen(pass);
    FILE *f = fopen(argv[2], "r");
    if (!f) return 1;
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(len + 1);
    long read_len = fread(buf, 1, len, f);
    fclose(f);

    int out_len = 0;
    unsigned char *out = malloc(len);
    for (long i = 0; i < read_len; i += 4) {
        int n[4];
        for(int j=0; j<4; j++) {
            if (i+j < read_len && buf[i+j] != '=' && buf[i+j] != '\n' && buf[i+j] != '\r') {
                n[j] = b64_inv(buf[i+j]);
            } else {
                n[j] = -1;
            }
        }
        if (n[0] == -1 || n[1] == -1) break;
        out[out_len++] = (n[0] << 2) | (n[1] >> 4);
        if (n[2] != -1) out[out_len++] = ((n[1] & 15) << 4) | (n[2] >> 2);
        if (n[3] != -1) out[out_len++] = ((n[2] & 3) << 6) | n[3];
    }

    for (int i = 0; i < out_len; i++) {
        putchar(out[i] ^ pass[i % pass_len]);
    }
    free(buf);
    free(out);
    return 0;
}
EOF

    # Compile and strip the binary
    gcc /app/decoder.c -o /app/legacy_decoder -s
    rm /app/decoder.c

    # Create the python generator script
    cat << 'EOF' > /app/generate.py
import os, base64, random, json

def encode_payload(data, pwd="trace"):
    xored = bytes([b ^ pwd[i % len(pwd)].encode()[0] for i, b in enumerate(data.encode())])
    return base64.b64encode(xored).decode()

def make_payloads(dir_path, is_evil, count=50):
    os.makedirs(dir_path, exist_ok=True)
    evils = ["<script>evil()</script>", "' OR 1=1 --", "\\x90\\x90\\x90\\x90\\x90"]
    for i in range(count):
        content = {"id": i, "status": "ok", "val": random.randint(1000, 9999)}
        data = f"AUDIT_ENTRY:{json.dumps(content)}"
        if is_evil:
            data += random.choice(evils)
        encoded = encode_payload(data)
        with open(os.path.join(dir_path, f"payload_{i:02d}.enc"), "w") as f:
            f.write(encoded)

make_payloads("/app/corpus/clean", False)
make_payloads("/app/corpus/evil", True)
make_payloads("/app/corpus/holdout_clean", False)
make_payloads("/app/corpus/holdout_evil", True)
EOF

    # Generate payloads
    python3 /app/generate.py
    rm /app/generate.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
