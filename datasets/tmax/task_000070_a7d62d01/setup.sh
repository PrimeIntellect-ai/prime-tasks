#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest hypothesis fastapi pydantic uvicorn requests

    mkdir -p /app/pr_workspace
    cd /app/pr_workspace

    # Create the C source for the shared library
    cat << 'EOF' > fastxor.c
#include <stddef.h>

int mask_payload(unsigned char* buffer, int length, unsigned char key) {
    if (buffer == NULL) return -1;
    for (int i = 0; i < length; i++) {
        buffer[i] ^= key;
    }
    return 0;
}
EOF

    # Compile and strip the shared library
    gcc -fPIC -shared -O3 fastxor.c -o libfastxor.so
    strip --strip-all libfastxor.so
    rm fastxor.c

    # Create the broken Python wrapper
    cat << 'EOF' > wrapper.py
import ctypes
import os

lib = ctypes.CDLL(os.path.abspath(os.path.join(os.path.dirname(__file__), 'libfastxor.so')))

# INCORRECT ABI BINDINGS INTENTIONALLY PROVIDED TO AGENT
lib.mask_payload.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
lib.mask_payload.restype = None

def apply_mask(data: bytes, key: int) -> bytes:
    # BUG: strings are immutable in Python, passing data directly and letting C mutate it causes a segfault.
    # The agent needs to use ctypes.create_string_buffer
    lib.mask_payload(data, len(data), key)
    return data
EOF

    # Create the property-based tests
    cat << 'EOF' > test_wrapper.py
from hypothesis import given, strategies as st
from wrapper import apply_mask

@given(st.binary(), st.integers(min_value=0, max_value=255))
def test_mask_roundtrip(data, key):
    masked = apply_mask(data, key)
    assert len(masked) == len(data)
    unmasked = apply_mask(masked, key)
    assert unmasked == data
EOF

    # Create the skeleton server
    cat << 'EOF' > server.py
from fastapi import FastAPI
from pydantic import BaseModel
import base64
from wrapper import apply_mask

app = FastAPI()

# TODO: Implement the /mask endpoint here
EOF

    # Set permissions
    chmod -R 777 /app/pr_workspace

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
