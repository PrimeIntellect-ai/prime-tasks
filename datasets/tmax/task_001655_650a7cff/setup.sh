#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Create dict.csv
    cat << 'EOF' > /home/user/dict.csv
LEGACY_SYSTEM,NEW_SYSTEM
TEMP_VAR,PERM_VAR
EOF

    # Generate memo.wav
    espeak -w /app/memo.wav "For our custom text compression, scan the text for any sequence of three or more consecutive identical characters. Whenever you find three or more identical characters in a row, replace the entire sequence with a tilde, followed by the character, followed by the total count of that character in the sequence, and then another tilde. For example, if you see five capital A's in a row, replace it with tilde capital A five tilde."

    # Create oracle_process
    cat << 'EOF' > /app/oracle_process
#!/usr/bin/env python3
import sys
import re
import csv

def process():
    # Load dict
    substitutions = []
    with open('/home/user/dict.csv', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 2:
                substitutions.append((row[0], row[1]))

    text_lines = sys.stdin.read().splitlines()

    out_lines = []
    for i, line in enumerate(text_lines):
        # 1. Substitute
        for old, new in substitutions:
            line = line.replace(old, new)

        # 2. Custom Compression (RLE for 3+ chars)
        def rle_repl(match):
            chars = match.group(0)
            return f"~{chars[0]}{len(chars)}~"

        line = re.sub(r'(.)\1{2,}', rle_repl, line)

        # 3. Line Numbering
        out_lines.append(f"{i+1:03d}: {line}")

    for o in out_lines:
        print(o)

if __name__ == '__main__':
    process()
EOF
    chmod +x /app/oracle_process

    chmod -R 777 /home/user
    chmod -R 777 /app
