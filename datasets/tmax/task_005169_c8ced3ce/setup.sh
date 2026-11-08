#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip curl build-essential openssl
    pip3 install pytest

    # Install Rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    export PATH="/root/.cargo/bin:$PATH"

    # Setup goblin crate
    mkdir -p /app
    cd /app
    curl -L https://crates.io/api/v1/crates/goblin/0.7.1/download -o goblin.tar.gz
    tar -xzf goblin.tar.gz
    rm goblin.tar.gz
    # Modify Cargo.toml
    sed -i 's/edition = "2021"/edition = "2015"/' goblin-0.7.1/Cargo.toml

    # Setup oracle
    mkdir -p /opt/oracle
    cat << 'EOF' > /opt/oracle/decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

static const int b64[256] = {
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,62,-1,-1,-1,63,
    52,53,54,55,56,57,58,59,60,61,-1,-1,-1,-1,-1,-1,
    -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9,10,11,12,13,14,
    15,16,17,18,19,20,21,22,23,24,25,-1,-1,-1,-1,-1,
    -1,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,
    41,42,43,44,45,46,47,48,49,50,51,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,
    -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
};

int main() {
    char *line = NULL;
    size_t len = 0;
    ssize_t read = getline(&line, &len, stdin);
    if (read == -1) {
        printf("INVALID_ELF\n");
        return 1;
    }
    if (read > 0 && line[read-1] == '\n') line[read-1] = '\0';
    if (read > 1 && line[read-2] == '\r') line[read-2] = '\0';

    size_t in_len = strlen(line);
    if (in_len % 4 != 0) {
        printf("INVALID_ELF\n");
        return 1;
    }

    size_t out_len = in_len / 4 * 3;
    if (in_len > 0 && line[in_len-1] == '=') out_len--;
    if (in_len > 1 && line[in_len-2] == '=') out_len--;

    uint8_t *out = malloc(out_len);
    if (!out) return 1;

    for (size_t i = 0, j = 0; i < in_len; ) {
        int a = line[i] == '=' ? 0 : b64[(unsigned char)line[i]]; i++;
        int b = line[i] == '=' ? 0 : b64[(unsigned char)line[i]]; i++;
        int c = line[i] == '=' ? 0 : b64[(unsigned char)line[i]]; i++;
        int d = line[i] == '=' ? 0 : b64[(unsigned char)line[i]]; i++;

        if (a == -1 || b == -1 || c == -1 || d == -1) {
            printf("INVALID_ELF\n");
            return 1;
        }

        uint32_t trip = (a << 18) | (b << 12) | (c << 6) | d;
        if (j < out_len) out[j++] = (trip >> 16) & 0xFF;
        if (j < out_len) out[j++] = (trip >> 8) & 0xFF;
        if (j < out_len) out[j++] = trip & 0xFF;
    }

    for (size_t i = 0; i < out_len; i++) {
        out[i] ^= 0x5A;
    }

    if (out_len < 4 || out[0] != 0x7F || out[1] != 0x45 || out[2] != 0x4C || out[3] != 0x46) {
        printf("INVALID_ELF\n");
        return 1;
    }

    fwrite(out, 1, out_len, stdout);
    return 0;
}
EOF
    gcc -O3 /opt/oracle/decoder.c -o /opt/oracle/decoder

    # Create user
    useradd -m -s /bin/bash user || true

    # Ensure home permissions
    chmod -R 777 /home/user
