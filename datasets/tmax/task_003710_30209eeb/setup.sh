#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest pandas

    # Create directories
    mkdir -p /app/vendored/pii-masker/pii_masker
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Create vendored package setup.py
    cat << 'EOF' > /app/vendored/pii-masker/setup.py
from setuptools import setup, find_packages

setup(
    name='pii-masker',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    # Create vendored package __init__.py
    cat << 'EOF' > /app/vendored/pii-masker/pii_masker/__init__.py
from .masker import mask_text
EOF

    # Create vendored package rules.py with deliberate errors
    cat << 'EOF' > /app/vendored/pii-masker/pii_masker/rules.py
import re

SSN_REGEX = re.compile(r'\b\d{3}-\d{2}-\d{4}')
EMAIL_REGEX = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
EOF

    # Create vendored package masker.py
    cat << 'EOF' > /app/vendored/pii-masker/pii_masker/masker.py
from .rules import SSN_REGEX, EMAIL_REGEX

def mask_text(text):
    text = SSN_REGEX.sub('[SSN]', text)
    text = EMAIL_REGEX.sub('[EMAIL]', text)
    return text
EOF

    # Create evil corpus
    cat << 'EOF' > /app/corpora/evil/evil_1.csv
user_id,date,feedback
1,2023-01-01,My SSN is 111-22-3333 and email is a@b.com
1,2023-01-02,Duplicate row should be removed
2,2023-01-01,Contact me at test@example.com
EOF

    cat << 'EOF' > /app/corpora/evil/evil_2.csv
user_id,date,feedback
3,2023-01-01,SSN: 999-88-7777
EOF

    # Create clean corpus
    cat << 'EOF' > /app/corpora/clean/clean_1.csv
user_id,date,feedback
4,2023-01-01,Serial 123-45-67891
4,2023-01-02,Duplicate row should be removed
5,2023-01-01,Twitter @company
EOF

    cat << 'EOF' > /app/corpora/clean/clean_2.csv
user_id,date,feedback
6,2023-01-01,Part number 987-65-43210
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
