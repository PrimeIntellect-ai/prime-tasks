#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu-core
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/process_logs.sh
#!/bin/bash
PREFIX="UNKNOWN"
while IFS= read -r line; do
    clean=$(echo "$line" | sed 's/[^A-Za-z0-9+/=]//g')
    if [ -z "$clean" ]; then
        echo "CORRUPT_LOG"
        continue
    fi
    decoded=""
    attempt="$clean"
    while true; do
        decoded=$(echo "$attempt" | base64 -d 2>/dev/null)
        if [ $? -eq 0 ]; then
            break
        fi
        attempt="${attempt}="
    done
    hex_decoded=$(echo "$decoded" | xxd -r -p 2>/dev/null)
    if [ -z "$hex_decoded" ]; then
        echo "CORRUPT_LOG"
    else
        echo "$PREFIX: $hex_decoded"
    fi
done < "$1"
EOF
    chmod +x /app/process_logs.sh

    convert -background black -fill white -font DejaVu-Sans -pointsize 36 label:'EMRG' /app/prefix_config.png

    cat << 'EOF' > /app/oracle_parser
#!/usr/bin/env python3
import sys
import re
import base64
import binascii

def process_file(filepath):
    prefix = "EMRG"
    with open(filepath, 'r') as f:
        for line in f:
            clean = re.sub(r'[^A-Za-z0-9+/=]', '', line)
            if not clean:
                print("CORRUPT_LOG")
                continue

            decoded = None
            for pad_count in range(3):
                attempt = clean + ("=" * pad_count)
                try:
                    # strict decoding to ensure padding is correct
                    decoded_bytes = base64.b64decode(attempt, validate=True)
                    decoded = decoded_bytes.decode('ascii')
                    break
                except Exception:
                    pass

            if decoded is None:
                print("CORRUPT_LOG")
                continue

            try:
                # remove any newlines from the base64 decode if present
                decoded = decoded.strip()
                if not decoded:
                    raise ValueError
                ascii_text = binascii.unhexlify(decoded).decode('ascii')
                print(f"{prefix}: {ascii_text}")
            except Exception:
                print("CORRUPT_LOG")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        process_file(sys.argv[1])
EOF
    chmod +x /app/oracle_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
