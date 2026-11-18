#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr
    pip3 install pytest

    mkdir -p /app

    # Create the image
    convert -background white -fill black -pointsize 24 label:"COMPRESSION CONFIGURATION\nESCAPE: ^\nMIN_RUN: 6" /app/config.png

    # Create the oracle
    cat << 'EOF' > /app/oracle_compress
#!/usr/bin/env python3
import sys

def compress(text, escape_char='^', min_run=6):
    if not text:
        return ""

    result = []
    n = len(text)
    i = 0

    while i < n:
        char = text[i]
        count = 1
        while i + count < n and text[i + count] == char:
            count += 1

        if count >= min_run:
            if char == escape_char:
                result.append(f"{escape_char}{escape_char}{count}{escape_char}")
            else:
                result.append(f"{escape_char}{char}{count}{escape_char}")
            i += count
        else:
            for _ in range(count):
                if char == escape_char:
                    result.append(f"{escape_char}{escape_char}")
                else:
                    result.append(char)
            i += count

    return "".join(result)

if __name__ == "__main__":
    input_data = sys.stdin.read()
    sys.stdout.write(compress(input_data))
EOF
    chmod +x /app/oracle_compress

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
