#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest hypothesis packaging

    mkdir -p /home/user/app
    cd /home/user/app

    cat << 'EOF' > semver_check.c
#include <stdint.h>
#include <string.h>

// Custom data structure: packed 16-bit integers for SemVer
struct Version {
    uint16_t major;
    uint16_t minor;
    uint16_t patch;
} __attribute__((packed));

// Decodes a simple custom base64-like structure into the Version struct
// (For the sake of this test, the Python side passes the raw struct bytes as a buffer, 
// so we just cast it. The "base64" decode happens at the edge, simulated here.)
int is_greater_or_equal(const unsigned char* raw_struct_bytes, uint16_t m2, uint16_t min2, uint16_t p2) {
    struct Version* v1 = (struct Version*)raw_struct_bytes;

    // BUGGY MATHEMATICAL LOGIC: Fails to properly evaluate lexicographical order
    if (v1->major > m2) return 1;
    if (v1->major == m2 && v1->minor >= min2) {
        // Bug is here: if minor == min2, it doesn't check patch correctly
        // It just returns 1 if minor >= min2.
        return 1;
    }
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: libsemver.so

libsemver.so: semver_check.c
	gcc -o libsemver.so semver_check.c
EOF

    cat << 'EOF' > test_semver.py
import ctypes
import struct
from packaging import version
from hypothesis import given, settings
import hypothesis.strategies as st
import os

# Load the C library
lib = ctypes.CDLL(os.path.abspath(os.path.join(os.path.dirname(__file__), 'libsemver.so')))

lib.is_greater_or_equal.argtypes = [ctypes.c_char_p, ctypes.c_uint16, ctypes.c_uint16, ctypes.c_uint16]
lib.is_greater_or_equal.restype = ctypes.c_int

@settings(max_examples=1000)
@given(
    st.tuples(
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100)
    ),
    st.tuples(
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100),
        st.integers(min_value=0, max_value=100)
    )
)
def test_semver_comparison(v1, v2):
    # Pack v1 into custom struct bytes (uint16 little endian)
    raw_bytes = struct.pack('<HHH', v1[0], v1[1], v1[2])

    # Call C function
    c_res = lib.is_greater_or_equal(raw_bytes, v2[0], v2[1], v2[2])

    # Python source of truth
    pv1 = version.parse(f"{v1[0]}.{v1[1]}.{v1[2]}")
    pv2 = version.parse(f"{v2[0]}.{v2[1]}.{v2[2]}")
    expected = 1 if pv1 >= pv2 else 0

    assert c_res == expected, f"Failed for {v1} >= {v2}. Expected {expected}, got {c_res}"
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
