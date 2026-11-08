#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-dev gcc make build-essential
    pip3 install pytest

    # Create directories
    mkdir -p /app/vendor/libsectoken-1.2.0/src
    mkdir -p /app/vendor/libsectoken-1.2.0/include
    mkdir -p /opt/legacy

    # Create the legacy reference binary
    cat << 'EOF' > /opt/legacy/rotate_tokens_ref
#!/usr/bin/env python3
import sys
import hashlib

def main():
    if len(sys.argv) != 3:
        sys.exit(1)
    seed = sys.argv[1]
    user_id = sys.argv[2]

    h = hashlib.sha256(seed.encode()).hexdigest()
    raw = h + str(user_id)

    for c in ['<', '>', "'", '"', '&']:
        raw = raw.replace(c, '')

    print(raw)

if __name__ == '__main__':
    main()
EOF
    chmod +x /opt/legacy/rotate_tokens_ref

    # Create libsectoken files
    # Makefile with spaces instead of tabs and wrong include path
    cat << 'EOF' > /app/vendor/libsectoken-1.2.0/Makefile
all:
        gcc -shared -o libsectoken.so -fPIC -I/wrong/path src/validate.c
EOF

    # src/validate.c with strcmp (timing leak)
    cat << 'EOF' > /app/vendor/libsectoken-1.2.0/src/validate.c
#include <string.h>

int validate_token(const char* a, const char* b) {
    return strcmp(a, b) == 0;
}
EOF

    # include/validate.h
    cat << 'EOF' > /app/vendor/libsectoken-1.2.0/include/validate.h
int validate_token(const char* a, const char* b);
EOF

    # setup.py
    cat << 'EOF' > /app/vendor/libsectoken-1.2.0/setup.py
from setuptools import setup, Extension

setup(
    name='libsectoken',
    version='1.2.0',
    py_modules=['libsectoken'],
    data_files=[('', ['libsectoken.so'])],
)
EOF

    # libsectoken.py
    cat << 'EOF' > /app/vendor/libsectoken-1.2.0/libsectoken.py
import ctypes
import os

def generate_and_validate(a, b):
    lib_path = os.path.join(os.path.dirname(__file__), 'libsectoken.so')
    if not os.path.exists(lib_path):
        lib_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'libsectoken.so')
    try:
        lib = ctypes.CDLL(lib_path)
        return lib.validate_token(a.encode(), b.encode())
    except Exception:
        return False
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
