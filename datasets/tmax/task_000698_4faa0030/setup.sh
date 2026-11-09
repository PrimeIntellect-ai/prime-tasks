#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    # Create directories
    mkdir -p /app/minidiff-v1.2/minidiff
    mkdir -p /app/oracle

    # Create buggy minidiff/core.py
    cat << 'EOF' > /app/minidiff-v1.2/minidiff/core.py
def _pure_python_delta(text1, text2):
    chunks = text2.split('\n')
    # Bug: trailing empty lines are stripped
    while chunks and not chunks[-1]:
        chunks.pop()
    return "DELTA:" + "|".join(chunks)

def generate_delta(text1, text2):
    return _pure_python_delta(text1, text2)
EOF

    # Create minidiff/__init__.py
    cat << 'EOF' > /app/minidiff-v1.2/minidiff/__init__.py
from .core import generate_delta
EOF

    # Create oracle script
    cat << 'EOF' > /tmp/oracle.py
import sys

def generate_delta(text1, text2):
    chunks = text2.split('\n')
    return "DELTA:" + "|".join(chunks)

if __name__ == "__main__":
    if len(sys.argv) == 3:
        with open(sys.argv[1], 'r') as f1, open(sys.argv[2], 'r') as f2:
            print(generate_delta(f1.read(), f2.read()))
EOF

    # Compile oracle to pyc
    python3 -c "import py_compile; py_compile.compile('/tmp/oracle.py', '/app/oracle/minidiff_oracle.pyc')"
    chmod +x /app/oracle/minidiff_oracle.pyc
    rm /tmp/oracle.py

    # Create setup.py for the vendored package
    cat << 'EOF' > /app/minidiff-v1.2/setup.py
from setuptools import setup
setup(
    name='minidiff',
    version='1.2',
    packages=['minidiff'],
)
EOF

    # Install the buggy package
    pip3 install -e /app/minidiff-v1.2

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
