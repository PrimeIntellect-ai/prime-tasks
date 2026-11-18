#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc netcat-openbsd ltrace strace binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Create C source for exfil_decoder
    cat << 'EOF' > /app/exfil_decoder.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 5) return 1;
    if (strcmp(argv[1], "--key") != 0) return 1;
    if (strcmp(argv[2], "Sup3rS3cr3tK3y!") != 0) return 1;
    if (strcmp(argv[3], "--decode") != 0) return 1;

    char *hex = argv[4];
    int len = strlen(hex);
    char *key = argv[2];
    int key_len = strlen(key);

    for (int i = 0; i < len; i += 2) {
        char byte_str[3] = {hex[i], hex[i+1], 0};
        unsigned char byte = (unsigned char)strtol(byte_str, NULL, 16);
        unsigned char decoded = byte ^ key[(i/2) % key_len];
        printf("%c", decoded);
    }
    return 0;
}
EOF

    gcc -s -o /app/exfil_decoder /app/exfil_decoder.c
    rm /app/exfil_decoder.c

    # Generate syslog
    cat << 'EOF' > /tmp/gen_syslog.py
import binascii

key = b"Sup3rS3cr3tK3y!"
plaintext = b"EVIDENCE_FLAG{TH3_QU1CK_BR0WN_F0X_JUMPS_0V3R_TH3_L4ZY_D0G_99321}"

def xor(data, key):
    return bytes([data[i] ^ key[i % len(key)] for i in range(len(data))])

c1 = plaintext[:31]
c2 = plaintext[31:]

h1 = binascii.hexlify(xor(c1, key)).decode()
h2 = binascii.hexlify(xor(c2, key)).decode()

syslog_content = f"""Jan 12 10:00:00 host kernel: Normal log entry
Jan 12 10:00:01 host kernel: [SYSTEM_ALERT_909] Payload chunk: {h1}
Jan 12 10:05:00 host kernel: Normal log entry
Jan 12 10:10:01 host kernel: [SYSTEM_ALERT_909] Payload chunk: {h2}
Jan 12 10:15:00 host kernel: Normal log entry
"""

with open("/home/user/syslog", "w") as f:
    f.write(syslog_content)
EOF

    python3 /tmp/gen_syslog.py
    rm /tmp/gen_syslog.py

    chmod -R 777 /home/user
    chmod 644 /home/user/syslog
