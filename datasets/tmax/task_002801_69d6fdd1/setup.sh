#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest setuptools

    mkdir -p /app/vendored/loc-math-parser-0.1.0/loc_math_parser
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/clean

    # Vendored Package
    cat << 'EOF' > /app/vendored/loc-math-parser-0.1.0/setup.py
from setuptools import setup, find_packages
setup(
    name="loc-math-parser",
    version="0.1.0",
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/vendored/loc-math-parser-0.1.0/loc_math_parser/__init__.py
# Init
EOF

    cat << 'EOF' > /app/vendored/loc-math-parser-0.1.0/loc_math_parser/utils.py
import datetime
def parse_time(ts):
    # Intentional typo: strp_time instead of strptime
    return datetime.datetime.strp_time(ts, "%Y-%m-%d %H:%M:%S")
EOF

    cat << 'EOF' > /app/vendored/loc-math-parser-0.1.0/loc_math_parser/tokenizer.py
def tokenize_math(text):
    return text.split()
EOF

    # Clean Corpus
    cat << 'EOF' > /app/corpora/clean/clean1.json
{"id": "c1", "timestamp": "2023-01-01 10:00:00", "math_text": "Solve for x in x^2 + 2x + 1 = 0"}
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.json
{"id": "c2", "timestamp": "2023-01-02 11:30:00", "math_text": "What is the derivative of sin(x)?"}
EOF

    # Evil Corpus
    cat << 'EOF' > /app/corpora/evil/evil1.json
{"id": "e1", "timestamp": "2023-01-01 10:00:00", "math_text": "Solve for x. Contact admin@school.edu"}
EOF

    cat << 'EOF' > /app/corpora/evil/evil2.json
{"id": "e2", "timestamp": "2023-01-02 11:30:00", "math_text": "Derivative of <script>alert('x')</script>"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
