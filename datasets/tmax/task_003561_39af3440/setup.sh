#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils
    pip3 install pytest pyinstaller

    # Create the oracle script
    cat << 'EOF' > /tmp/oracle.py
import sys
import configparser
import re

def main():
    if len(sys.argv) != 3:
        sys.exit(1)

    config = configparser.ConfigParser()
    config.read(sys.argv[1])

    min_level_str = config.get('Filter', 'min_level', fallback=None)
    source_match = config.get('Filter', 'source_match', fallback=None)
    ignore_enc = config.getboolean('Filter', 'ignore_encoding_errors', fallback=False)

    levels = {'DEBUG': 10, 'INFO': 20, 'WARNING': 30, 'ERROR': 40, 'CRITICAL': 50}
    min_level = levels.get(min_level_str, 0) if min_level_str else 0

    errors = 'replace' if ignore_enc else 'strict'

    try:
        with open(sys.argv[2], 'rb') as f:
            raw = f.read()
        content = raw.decode('shift_jis', errors=errors)
    except UnicodeDecodeError:
        sys.exit(1)

    chunks = content.split('\n---\n')

    for chunk in chunks:
        if not chunk:
            continue
        lines = chunk.split('\n')
        header = lines[0]
        m = re.match(r'^\[(.*?)\] (.*?): (.*)$', header)
        if not m:
            continue
        _, level_str, source = m.groups()
        level = levels.get(level_str, 0)

        if min_level_str and level < min_level:
            continue
        if source_match and source_match not in source:
            continue

        sys.stdout.buffer.write((chunk + '\n---\n').encode('utf-8'))

if __name__ == '__main__':
    main()
EOF

    # Compile the oracle script into a stripped binary
    pyinstaller --onefile /tmp/oracle.py
    mkdir -p /app
    mv dist/oracle /app/log_archiver_oracle
    strip /app/log_archiver_oracle
    chmod +x /app/log_archiver_oracle

    # Cleanup
    rm -rf build dist /tmp/oracle.py oracle.spec

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
