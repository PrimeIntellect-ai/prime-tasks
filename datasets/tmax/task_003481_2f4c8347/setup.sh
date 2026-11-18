#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cmake g++ make libssl-dev git curl
    pip3 install pytest PyJWT

    mkdir -p /app/auditor-tool/vendor
    mkdir -p /app/corpus/clean
    mkdir -p /app/corpus/evil

    # Clone jwt-cpp v0.6.0
    git clone --branch v0.6.0 https://github.com/Thalhammer/jwt-cpp.git /app/auditor-tool/vendor/jwt-cpp

    # Create CMakeLists.txt
    cat << 'EOF' > /app/auditor-tool/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(Validator)
set(CMAKE_CXX_STANDARD 11)
include_directories(vendor/jwt-cpp/include)
add_executable(validator main.cpp)
# Deliberately missing OpenSSL linking
EOF

    # Create main.cpp
    cat << 'EOF' > /app/auditor-tool/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include "jwt-cpp/jwt.h"

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string token((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    // TODO: Validate token and print VALID or INVALID
    return 0;
}
EOF

    # Generate Corpus
    cat << 'EOF' > /tmp/gen_corpus.py
import jwt
import time
import json
import base64

secret = "ssh-audit-secret-2024"

# Clean tokens
for i in range(5):
    payload = {"role": "auditor", "exp": int(time.time()) + 3600, "id": i}
    token = jwt.encode(payload, secret, algorithm="HS256")
    with open(f"/app/corpus/clean/token_{i}.jwt", "w") as f:
        f.write(token)

# Evil tokens
# 1. none alg
payload = {"role": "auditor", "exp": int(time.time()) + 3600}
header = {"alg": "none", "typ": "JWT"}
b64_header = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
b64_payload = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
token_none = f"{b64_header}.{b64_payload}."
with open("/app/corpus/evil/token_1.jwt", "w") as f:
    f.write(token_none)

# 2. expired
payload = {"role": "auditor", "exp": int(time.time()) - 3600}
token_exp = jwt.encode(payload, secret, algorithm="HS256")
with open("/app/corpus/evil/token_2.jwt", "w") as f:
    f.write(token_exp)

# 3. wrong secret
payload = {"role": "auditor", "exp": int(time.time()) + 3600}
token_wrong = jwt.encode(payload, "wrong-secret", algorithm="HS256")
with open("/app/corpus/evil/token_3.jwt", "w") as f:
    f.write(token_wrong)

# 4. wrong role
payload = {"role": "admin", "exp": int(time.time()) + 3600}
token_role = jwt.encode(payload, secret, algorithm="HS256")
with open("/app/corpus/evil/token_4.jwt", "w") as f:
    f.write(token_role)

# 5. modified payload
payload = {"role": "auditor", "exp": int(time.time()) + 3600}
token_orig = jwt.encode(payload, secret, algorithm="HS256")
parts = token_orig.split(".")
payload_mod = {"role": "admin", "exp": int(time.time()) + 3600}
b64_payload_mod = base64.urlsafe_b64encode(json.dumps(payload_mod).encode()).decode().rstrip("=")
token_mod = f"{parts[0]}.{b64_payload_mod}.{parts[2]}"
with open("/app/corpus/evil/token_5.jwt", "w") as f:
    f.write(token_mod)
EOF

    python3 /tmp/gen_corpus.py
    rm /tmp/gen_corpus.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
