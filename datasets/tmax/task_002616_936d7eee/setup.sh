#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy
    cd /home/user/legacy

    cat << 'EOF' > decoder_fixed.c
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
    if (argc != 4) {
        return 1;
    }
    if (strcmp(argv[1], "--key") == 0 && strcmp(argv[2], "SuperSecretLegacyKey99") == 0) {
        // Simple XOR with 0x2A
        for(int i=0; i<strlen(argv[3]); i++) {
            putchar(argv[3][i] ^ 0x2A);
        }
        return 0;
    }
    return 1;
}
EOF

    gcc decoder_fixed.c -o legacy_decoder
    rm decoder_fixed.c

    cat << 'EOF' > service_a.log
1690000000,yOI^OG*I^K\^ON
1690000025,_IOX*FEEON*CD
EOF

    cat << 'EOF' > service_b.log
1690000010:446174616261736520636f6e6e6563746564
1690000030:5175657279206578656375746564
EOF

    cat << 'EOF' > aggregator.py
import json
import subprocess
import sys

def decode_hex(hex_str):
    res = ""
    i = 0
    # BUG: Infinite loop because i is not incremented correctly if we hit a condition, 
    # or just missing increment. Let's make it an infinite loop.
    while i < len(hex_str):
        res += chr(int(hex_str[i:i+2], 16))
        # Missing i += 2 here!
    return res

def decrypt_service_a(payload):
    # Missing the correct key flag and value
    # Should be: subprocess.check_output(['./legacy_decoder', '--key', 'SuperSecretLegacyKey99', payload])
    try:
        out = subprocess.check_output(['./legacy_decoder', '--key', 'UNKNOWN', payload])
        return out.decode('utf-8')
    except subprocess.CalledProcessError:
        return "DECRYPTION_FAILED"

def main():
    events = []

    # Parse Service A
    with open('service_a.log', 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            ts, payload = line.split(',')
            msg = decrypt_service_a(payload)
            events.append({"timestamp": int(ts), "service": "service_a", "message": msg})

    # Parse Service B
    with open('service_b.log', 'r') as f:
        for line in f:
            line = line.strip()
            if not line: continue
            ts, payload = line.split(':')
            msg = decode_hex(payload)
            events.append({"timestamp": int(ts), "service": "service_b", "message": msg})

    # Sort and output
    events.sort(key=lambda x: x["timestamp"])

    with open('/home/user/timeline.json', 'w') as f:
        json.dump(events, f, indent=2)

if __name__ == "__main__":
    main()
EOF

    chmod -R 777 /home/user
