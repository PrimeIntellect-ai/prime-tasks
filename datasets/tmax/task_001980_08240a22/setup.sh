#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app/vendored/i18n_ts_parser

    cat << 'EOF' > /app/vendored/i18n_ts_parser/__init__.py
from .extractor import extract
EOF

    cat << 'EOF' > /app/vendored/i18n_ts_parser/extractor.py
import re

PATTERN = re.compile(r"\[([0-9A-Z:\-]+)\]\s+([A-Z_]+)\s+([0-9.]+)")

def extract(line):
    match = PATTERN.search(line)
    if match:
        return match.groups()
    return None
EOF

    cat << 'EOF' > /app/oracle_parse_metrics.py
import sys
import re
import unicodedata

def normalize_digits(s):
    return ''.join(str(unicodedata.decimal(c, c)) if unicodedata.category(c) == 'Nd' else c for c in s)

def main():
    pattern = re.compile(r"(?:\[|【)([^\]】]+)(?:\]|】)\s+([A-Z_]+)\s+([0-9.\u0660-\u0669\uFF10-\uFF19]+)")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        match = pattern.search(line)
        if match:
            ts, metric, val = match.groups()
            ts = normalize_digits(ts)
            val = normalize_digits(val)
            print(f"{ts},{metric},{val}")

if __name__ == "__main__":
    main()
EOF

    chmod -R 755 /app

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
