#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install --default-timeout=100 pytest setuptools

    # Create directories
    mkdir -p /home/user/data
    mkdir -p /home/user/output
    mkdir -p /app/locparse/locparse

    # Create loc files
    cat << 'EOF' > /home/user/data/es.loc
# translation block
[GREETING]
Hola
[FAREWELL]
Adiós
[ERROR_404]
No encontrado
EOF

    cat << 'EOF' > /home/user/data/fr.loc
# translation block
[GREETING]
Bonjour
[FAREWELL]
Au revoir
[ERROR_404]
Non trouvé
EOF

    # Create template.json
    cat << 'EOF' > /home/user/template.json
{
  "messages": {
    "GREETING": "",
    "FAREWELL": "",
    "ERROR_404": ""
  }
}
EOF

    # Create locparse package
    cat << 'EOF' > /app/locparse/setup.py
from setuptools import setup, find_packages

setup(
    name='locparse',
    version='1.0.0',
    packages=find_packages(),
)
EOF

    cat << 'EOF' > /app/locparse/locparse/__init__.py
from .parser import parse
EOF

    cat << 'EOF' > /app/locparse/locparse/parser.py
def parse(text):
    result = {}
    lines = text.strip().split('\n')
    current_key = None
    for line in lines[:-1]:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('[') and line.endswith(']'):
            current_key = line[1:-1]
        elif current_key:
            result[current_key] = line
            current_key = None
    return result
EOF

    pip3 install -e /app/locparse

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app/locparse
