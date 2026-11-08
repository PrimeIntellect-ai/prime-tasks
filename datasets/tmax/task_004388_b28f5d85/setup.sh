#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake build-essential zlib1g-dev zip
    pip3 install pytest

    mkdir -p /app/vendor/libarchive_custom
    mkdir -p /home/user/repo

    # Create vendored package
    cat << 'EOF' > /app/vendor/libarchive_custom/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(libarchive_custom)
add_library(archive_custom STATIC archive_reader.cpp)
target_include_directories(archive_custom PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
# INTENTIONAL TYPO: zlib_mising instead of z
target_link_libraries(archive_custom PRIVATE zlib_mising)
install(TARGETS archive_custom DESTINATION lib)
install(FILES archive_reader.h DESTINATION include)
EOF

    cat << 'EOF' > /app/vendor/libarchive_custom/archive_reader.h
#pragma once
#include <cstdint>
#include <cstddef>
#include <string>

class ArchiveReader {
public:
    ArchiveReader(const uint8_t* data, size_t size);
    bool is_valid() const;
private:
    bool valid;
};
EOF

    cat << 'EOF' > /app/vendor/libarchive_custom/archive_reader.cpp
#include "archive_reader.h"
// INTENTIONAL MISSING INCLUDE: #include <stdexcept>

ArchiveReader::ArchiveReader(const uint8_t* data, size_t size) {
    if (!data) {
        throw std::runtime_error("Null data pointer");
    }
    valid = false;
    // Basic ZIP validation: check for End of Central Directory record signature
    if (size >= 22) {
        for (size_t i = size - 22; i > 0; --i) {
            if (data[i] == 0x50 && data[i+1] == 0x4b && data[i+2] == 0x05 && data[i+3] == 0x06) {
                valid = true;
                break;
            }
        }
    }
}

bool ArchiveReader::is_valid() const {
    return valid;
}
EOF

    # Create config
    cat << 'EOF' > /home/user/repo_config.json
{"target_dir": "/home/user/repo", "expected_magic": "0x41525400"}
EOF

    # Create Python generator for repo files
    cat << 'EOF' > /tmp/generate_repo.py
import os
import struct
import zipfile
import io
import random

repo_dir = "/home/user/repo"
os.makedirs(repo_dir, exist_ok=True)

def create_zip():
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, 'w') as zf:
        zf.writestr("test.txt", "hello world")
    return buf.getvalue()

valid_zip = create_zip()
corrupt_zip = valid_zip[:-10] + b'\x00'*10

valid_magic = struct.pack(">I", 0x41525400) + b'\x00'*12
bad_magic = struct.pack(">I", 0x42525400) + b'\x00'*12

# Generate 10000 files
for i in range(10000):
    subdir = os.path.join(repo_dir, f"{i // 1000}")
    os.makedirs(subdir, exist_ok=True)
    filepath = os.path.join(subdir, f"file_{i}.art")

    if i < 8000:
        data = valid_magic + valid_zip
    elif i < 9000:
        data = bad_magic + valid_zip
    else:
        data = valid_magic + corrupt_zip

    with open(filepath, 'wb') as f:
        f.write(data)
EOF
    python3 /tmp/generate_repo.py
    rm /tmp/generate_repo.py

    # Create reference scanner
    cat << 'EOF' > /home/user/reference_scanner.py
import os
import json
import struct
import zipfile
import io

def scan():
    with open("/home/user/repo_config.json") as f:
        config = json.load(f)

    target_dir = config["target_dir"]
    expected_magic = int(config["expected_magic"], 16)

    results = []

    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith(".art"):
                filepath = os.path.join(root, file)
                with open(filepath, "rb") as f:
                    header = f.read(16)
                    if len(header) < 16:
                        results.append((filepath, "BAD_HEADER"))
                        continue

                    magic = struct.unpack(">I", header[:4])[0]
                    if magic != expected_magic:
                        results.append((filepath, "BAD_HEADER"))
                        continue

                    payload = f.read()
                    try:
                        with zipfile.ZipFile(io.BytesIO(payload)) as zf:
                            if zf.testzip() is not None:
                                results.append((filepath, "CORRUPT_ARCHIVE"))
                            else:
                                results.append((filepath, "VALID"))
                    except zipfile.BadZipFile:
                        results.append((filepath, "CORRUPT_ARCHIVE"))

    with open("/home/user/scan_results.csv", "w") as f:
        for path, status in sorted(results):
            f.write(f"{path},{status}\n")

if __name__ == "__main__":
    scan()
EOF

    # Create verifier script
    cat << 'EOF' > /app/verify_speedup.py
import time
import subprocess
import sys

def main():
    start = time.time()
    subprocess.run(["python3", "/home/user/reference_scanner.py"], check=True)
    ref_time = time.time() - start

    start = time.time()
    subprocess.run(["/home/user/artifact_scanner"], check=True)
    opt_time = time.time() - start

    speedup = ref_time / opt_time
    print(f"Speedup: {speedup:.2f}x")
    if speedup >= 3.0:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
