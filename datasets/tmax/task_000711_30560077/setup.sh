#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make wget tar
    pip3 install pytest

    # Create app directory and download cJSON
    mkdir -p /app
    cd /app
    wget https://github.com/DaveGamble/cJSON/archive/refs/tags/v1.7.17.tar.gz
    tar -xzf v1.7.17.tar.gz
    rm v1.7.17.tar.gz

    # Corrupt the Makefile
    cd cJSON-1.7.17
    # cJSON 1.7.17 Makefile has CC = gcc
    sed -i 's/^CC = gcc/CC = broken-gcc-compiler/' Makefile
    # Just in case it's not found, append it at the top
    if ! grep -q "broken-gcc-compiler" Makefile; then
        sed -i '1i CC = broken-gcc-compiler' Makefile
    fi

    # Generate corpora
    mkdir -p /home/user/corpus/evil
    mkdir -p /home/user/corpus/clean

    cat << 'EOF' > /tmp/gen_corpus.py
import os
import json

# Generate clean
for i in range(50):
    with open(f'/home/user/corpus/clean/clean_{i}.json', 'w') as f:
        json.dump({"key": "value", "num": i, "nested": {"a": 1}}, f)

# Generate evil - malformed
for i in range(25):
    with open(f'/home/user/corpus/evil/malformed_{i}.json', 'w') as f:
        f.write('{"key": "value", "num": ' + str(i) + ', "nested": {"a": 1}') # missing closing brace

# Generate evil - exec_cmd
for i in range(25):
    with open(f'/home/user/corpus/evil/exec_{i}.json', 'w') as f:
        data = {"key": "value", "num": i}
        if i % 3 == 0:
            data["exec_cmd"] = "rm -rf /"
        elif i % 3 == 1:
            data["nested"] = {"exec_cmd": "ls"}
        else:
            data["arr"] = [{"exec_cmd": "echo"}]
        json.dump(data, f)
EOF
    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
