#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app

    # Generate voicemail.wav
    espeak -w /app/voicemail.wav "Make sure to scrub all references to Hummingbird."

    # Create oracle_redactor
    cat << 'EOF' > /app/oracle_redactor
#!/usr/bin/env python3
import sys
import re

def process(line):
    has_newline = line.endswith('\n')
    clean_line = line[:-1] if has_newline else line

    # 1. Redact CC
    clean_line = re.sub(r'(?<!\d)\d{16}(?!\d)', '[REDACTED_CC]', clean_line)

    # 2. Redact Project
    clean_line = clean_line.replace('Hummingbird', '[REDACTED_PROJECT]')

    # 3. CWE-89
    if "' OR 1=1 --" in clean_line:
        clean_line += " [CWE-89_DETECTED]"

    return clean_line + ('\n' if has_newline else '')

for line in sys.stdin:
    sys.stdout.write(process(line))
EOF
    chmod +x /app/oracle_redactor

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
