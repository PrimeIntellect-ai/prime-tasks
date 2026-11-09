#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make
    pip3 install pytest

    mkdir -p /home/user/mobile_pipeline
    cd /home/user/mobile_pipeline

    cat << 'EOF' > manifest_A.json
{
    "libNetwork": "2.1.3",
    "libUI": "1.15.2",
    "libAnalytics": "3.0.0",
    "libAuth": "1.2.9"
}
EOF

    cat << 'EOF' > manifest_B.json
{
    "libNetwork": "2.1.10",
    "libUI": "1.5.9",
    "libDatabase": "4.2.0",
    "libAuth": "1.2.9-beta.12345678901234567890"
}
EOF

    cat << 'EOF' > fast_semver.cpp
#include <iostream>
#include <cstring>

extern "C" {
    // Strips pre-release tags and returns just the base version string.
    // BUG: Fixed size buffer of 16 bytes, but input can be longer.
    void parse_version_core(const char* input, char* output) {
        char buffer[16];
        int i = 0;
        while (input[i] != '\0' && input[i] != '-') {
            buffer[i] = input[i];
            i++;
        }
        buffer[i] = '\0';
        strcpy(output, buffer);
    }
}
EOF

    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -fPIC -Wall -Wextra -O2
LDFLAGS = -shared

all: libfastsemver.so

libfastsemver.so: fast_semver.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f libfastsemver.so
EOF

    cat << 'EOF' > build_resolver.py
import json
import sys
import ctypes
import os

# Load the C++ library
lib_path = os.path.join(os.path.dirname(__file__), 'libfastsemver.so')
if not os.path.exists(lib_path):
    print("Error: libfastsemver.so not found. Please build it first.")
    sys.exit(1)

lib = ctypes.CDLL(lib_path)
lib.parse_version_core.argtypes = [ctypes.c_char_p, ctypes.c_char_p]

def get_base_version(version_str):
    out_buffer = ctypes.create_string_buffer(256)
    lib.parse_version_core(version_str.encode('utf-8'), out_buffer)
    return out_buffer.value.decode('utf-8')

def compare_versions(v1, v2):
    # BUG: Naive string comparison
    if v1 > v2:
        return 1
    elif v1 < v2:
        return -1
    return 0

def merge_manifests(file_a, file_b):
    with open(file_a, 'r') as f:
        manifest_a = json.load(f)
    with open(file_b, 'r') as f:
        manifest_b = json.load(f)

    merged = {}
    all_keys = set(manifest_a.keys()).union(set(manifest_b.keys()))

    for key in all_keys:
        val_a = manifest_a.get(key)
        val_b = manifest_b.get(key)

        if val_a and not val_b:
            merged[key] = val_a
        elif val_b and not val_a:
            merged[key] = val_b
        else:
            base_a = get_base_version(val_a)
            base_b = get_base_version(val_b)
            if compare_versions(base_a, base_b) >= 0:
                merged[key] = val_a
            else:
                merged[key] = val_b

    # Sort keys
    sorted_merged = {k: merged[k] for k in sorted(merged.keys())}

    with open('resolved_manifest.json', 'w') as f:
        json.dump(sorted_merged, f, indent=4)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python3 build_resolver.py <manifest_A> <manifest_B>")
        sys.exit(1)
    merge_manifests(sys.argv[1], sys.argv[2])
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
