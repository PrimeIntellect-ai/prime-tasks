#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake make g++ zip unzip curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Create config file
    cat << 'EOF' > /home/user/doc_rules.conf
ALLOWED_EXT=.md,.txt,.rst,.png
MAX_UNCOMPRESSED_TOTAL_MB=10
REJECT_HIDDEN=true
EOF

    # Create vendored library
    mkdir -p /app/vendored/miniz-cpp-0.1.0
    cd /app/vendored/miniz-cpp-0.1.0
    curl -sSL https://raw.githubusercontent.com/richgel999/miniz/master/miniz.h -o miniz.h
    curl -sSL https://raw.githubusercontent.com/richgel999/miniz/master/miniz.c -o miniz.cpp

    cat << 'EOF' > CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(miniz_cpp)

add_library(miniz_cpp SHARED minz.cpp)
EOF

    # Create corpora
    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Clean corpus
    mkdir -p /tmp/clean1 && echo "clean markdown" > /tmp/clean1/doc1.md && cd /tmp/clean1 && zip -r /app/corpora/clean/bundle1.zip .
    mkdir -p /tmp/clean2 && echo "clean text" > /tmp/clean2/doc2.txt && cd /tmp/clean2 && zip -r /app/corpora/clean/bundle2.zip .

    # Evil corpus
    # 1. corrupt_header.zip
    echo "This is definitely not a valid zip archive." > /app/corpora/evil/corrupt_header.zip

    # 2. has_exe.zip
    mkdir -p /tmp/evil1 && echo "malicious payload" > /tmp/evil1/malware.exe && cd /tmp/evil1 && zip -r /app/corpora/evil/has_exe.zip .

    # 3. huge_file.zip
    mkdir -p /tmp/evil2
    dd if=/dev/zero of=/tmp/evil2/huge.md bs=1M count=15
    cd /tmp/evil2 && zip -r /app/corpora/evil/huge_file.zip .

    # 4. hidden_secrets.zip
    mkdir -p /tmp/evil3/nested && echo "secret_key=12345" > /tmp/evil3/nested/.env && echo "normal file" > /tmp/evil3/readme.md && cd /tmp/evil3 && zip -r /app/corpora/evil/hidden_secrets.zip .

    chmod -R 777 /home/user
    chmod -R 777 /app
