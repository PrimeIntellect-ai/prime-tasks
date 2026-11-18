#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/encryptor.c
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

uint32_t state;

// Custom LCG: state = state * 0x5D588B65 + 0x2BCD
// Byte extracted: (state >> 24) & 0xFF
uint8_t next_byte() {
    state = state * 0x5D588B65 + 0x2BCD;
    return (uint8_t)(state >> 24);
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        printf("Usage: %s <seed> <input> <output>\n", argv[0]);
        return 1;
    }

    state = (uint32_t)strtoul(argv[1], NULL, 10);
    FILE *fin = fopen(argv[2], "rb");
    FILE *fout = fopen(argv[3], "wb");

    if (!fin || !fout) return 1;

    int c;
    while ((c = fgetc(fin)) != EOF) {
        fputc(c ^ next_byte(), fout);
    }

    fclose(fin);
    fclose(fout);
    return 0;
}
EOF

    gcc -O2 /home/user/encryptor.c -o /home/user/encryptor
    strip /home/user/encryptor
    rm /home/user/encryptor.c

    cat << 'EOF' > /home/user/case_notes.txt
Initial Triage Report:
- Malware variant identified: "CustomLCG-XOR"
- The attackers use a weak 32-bit LCG stream cipher.
- Known Plaintext: All encrypted files are prepended with the exact string:
CRIME_LOG_START{v1.0}\n
EOF

    cat << 'EOF' > /home/user/evidence.txt
CRIME_LOG_START{v1.0}
2023-10-24 11:00:00 - Encryption started
2023-10-24 11:05:00 - Exfiltrating local database
FLAG: 9a8b7c6d5e4f3g2h1i0j
2023-10-24 11:10:00 - Wiping traces
CRIME_LOG_END
EOF

    /home/user/encryptor 31337 /home/user/evidence.txt /home/user/evidence.bin
    rm /home/user/evidence.txt

    chmod -R 777 /home/user
