#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        gcc \
        netcat-openbsd \
        coreutils \
        gawk \
        sed \
        curl

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create C source for legacy_decoder
    cat << 'EOF' > /app/legacy_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int unb64(unsigned char c) {
    if (c >= 'A' && c <= 'Z') return c - 'A';
    if (c >= 'a' && c <= 'z') return c - 'a' + 26;
    if (c >= '0' && c <= '9') return c - '0' + 52;
    if (c == '+') return 62;
    if (c == '/') return 63;
    return 0;
}

void decode_and_xor(const char *input) {
    int len = strlen(input);
    while (len > 0 && (input[len-1] == '\n' || input[len-1] == '\r')) len--;

    int i = 0;
    while (i < len) {
        int b1 = unb64(input[i]);
        int b2 = i+1 < len ? unb64(input[i+1]) : 0;
        int b3 = i+2 < len ? unb64(input[i+2]) : 0;
        int b4 = i+3 < len ? unb64(input[i+3]) : 0;

        int val = (b1 << 18) | (b2 << 12) | (b3 << 6) | b4;

        if (i+1 < len) putchar(((val >> 16) & 0xFF) ^ 0x42);
        if (i+2 < len && input[i+2] != '=') putchar(((val >> 8) & 0xFF) ^ 0x42);
        if (i+3 < len && input[i+3] != '=') putchar((val & 0xFF) ^ 0x42);

        i += 4;
    }
    putchar('\n');
}

int main() {
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        decode_and_xor(line);
    }
    return 0;
}
EOF

    # Compile and strip the binary
    gcc -O2 /app/legacy_decoder.c -o /app/legacy_decoder
    strip /app/legacy_decoder
    rm /app/legacy_decoder.c

    # Generate mock data
    cat << 'EOF' > /tmp/generate_data.py
import base64
import random
import time

sensors = ['temp_a', 'Temp_A', 'TEMP_A', 'pressure_1', 'Pressure_1', 'humidity_X']

with open('/home/user/raw_sensor_logs.txt', 'w') as f:
    for i in range(10000):
        ts = int(time.time()) - random.randint(0, 100000)
        sensor = random.choice(sensors)

        r = random.random()
        if r < 0.1:
            val = str(random.randint(-100, -1))
        elif r < 0.15:
            val = "ERROR"
        else:
            val = str(random.randint(0, 100))

        csv_line = f"{ts},{sensor},{val}"
        xored = bytes([b ^ 0x42 for b in csv_line.encode('utf-8')])
        b64 = base64.b64encode(xored).decode('utf-8')
        f.write(b64 + '\n')
EOF

    python3 /tmp/generate_data.py
    rm /tmp/generate_data.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
