#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    mkdir -p /app/vendored/text_cleaner_lib/text_cleaner_lib

    cat << 'EOF' > /app/lookup.csv
user_id,region,risk_score
10,NA,15
42,EU,95
99,ASIA,80
100,NA,91
EOF

    cat << 'EOF' > /app/vendored/text_cleaner_lib/setup.py
from setuptools import setup, find_packages
setup(name='text_cleaner_lib', version='1.0', packages=find_packages())
EOF

    cat << 'EOF' > /app/vendored/text_cleaner_lib/text_cleaner_lib/__init__.py
from .redactor import redact_emails
from .tokenizer import tokenize_and_normalize
EOF

    cat << 'EOF' > /app/vendored/text_cleaner_lib/text_cleaner_lib/redactor.py
import regx as re  # DELIBERATE BUG

def redact_emails(text):
    return re.sub(r'[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+', '[REDACTED]', text)
EOF

    cat << 'EOF' > /app/vendored/text_cleaner_lib/text_cleaner_lib/tokenizer.py
import re
def tokenize_and_normalize(text):
    text = text.lower()
    text = re.sub(r'[^\w\s]', '', text)
    return text.split()
EOF

    cat << 'EOF' > /app/oracle_process_stream.py
import sys
import json
import csv
from text_cleaner_lib import redact_emails, tokenize_and_normalize

def load_lookup():
    d = {}
    with open('/app/lookup.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            d[int(row['user_id'])] = {'region': row['region'], 'risk_score': int(row['risk_score'])}
    return d

def main():
    lookup = load_lookup()
    for line in sys.stdin:
        if not line.strip(): continue
        data = json.loads(line)
        uid = data['user_id']
        info = lookup.get(uid, {'region': 'UNKNOWN', 'risk_score': 0})
        if info['risk_score'] > 90:
            continue

        msg = redact_emails(data['message'])
        tokens = tokenize_and_normalize(msg)

        out = {
            "user_id": uid,
            "region": info['region'],
            "clean_tokens": tokens,
            "timestamp": data['timestamp']
        }
        print(json.dumps(out))

if __name__ == '__main__':
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
