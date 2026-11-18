#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential libssl-dev
    pip3 install pytest pandas

    mkdir -p /app/sec-audit-lib-1.0/src /app/sec-audit-lib-1.0/include

    cat << 'EOF' > /app/sec-audit-lib-1.0/include/token_validator.h
#pragma once
#include <string>
namespace SecAudit {
    bool ValidateToken(const std::string& token);
}
EOF

    cat << 'EOF' > /app/sec-audit-lib-1.0/src/token_validator.cpp
#include "token_validator.h"
#include <openssl/hmac.h>
#include <openssl/sha.h>
#include <string.h>

const std::string SECRET_KEY = "my_super_secret_key";

bool VerifyHMAC(const std::string& token, const std::string& key) {
    size_t pos = token.find(':');
    if (pos == std::string::npos) return false;
    std::string data = token.substr(0, pos);
    std::string mac_hex = token.substr(pos + 1);

    unsigned char* digest;
    unsigned int len = 0;
    digest = HMAC(EVP_sha256(), key.c_str(), key.length(), (unsigned char*)data.c_str(), data.length(), NULL, &len);

    char mdString[65];
    for(unsigned int i = 0; i < len; i++)
        sprintf(&mdString[i*2], "%02x", (unsigned int)digest[i]);
    mdString[64] = '\0';

    return mac_hex == std::string(mdString);
}

namespace SecAudit {
    bool ValidateToken(const std::string& token) {
        return true; // TODO: implement HMAC check
    }
}
EOF

    cat << 'EOF' > /app/sec-audit-lib-1.0/Makefile
CXX = g++
CXXFLAGS = -Iinclude -Wall -Wextra -std=c++17

all: libsecaudit.a

libsecaudit.a: token_validator.o
	ar rcs $@ $^

token_validator.o: src/token_validator.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f *.o *.a
EOF

    cat << 'EOF' > /app/setup.py
import os
import hashlib
import random
import hmac

os.makedirs('/tmp/configs', exist_ok=True)
os.makedirs('/home/user', exist_ok=True)

targets = []
expected = []
secret = b"my_super_secret_key"

server_code = """import socket, threading, time
def handle_client(c, token):
    try:
        c.sendall((token + '\\n').encode())
    except:
        pass
    finally:
        c.close()

def start_server(port, token):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(5)
    while True:
        c, _ = s.accept()
        threading.Thread(target=handle_client, args=(c, token), daemon=True).start()
"""

for i in range(100):
    port = 8000 + i
    conf_path = f"/tmp/configs/config_{port}.conf"
    with open(conf_path, 'w') as f:
        f.write(f"config data for {port}\n")

    with open(conf_path, 'rb') as f:
        real_sha = hashlib.sha256(f.read()).hexdigest()

    expected_sha = real_sha
    status = "SECURE"

    r = random.random()
    is_tampered = False
    is_perms = False
    is_token = False

    if r < 0.15:
        expected_sha = "deadbeef" * 8
        is_tampered = True
        status = "TAMPERED"
    elif r < 0.35:
        os.chmod(conf_path, 0o666)
        is_perms = True
        status = "VULNERABLE_PERMS"
    elif r < 0.65:
        is_token = True
        status = "VULNERABLE_TOKEN"

    targets.append(f"{port},{conf_path},{expected_sha}")
    expected.append(f"{port},{status}")

    data = f"service_{port}".encode()
    if is_token:
        mac = "badmac"
    else:
        mac = hmac.new(secret, data, hashlib.sha256).hexdigest()
    token = f"service_{port}:{mac}"

    server_code += f"threading.Thread(target=start_server, args=({port}, '{token}'), daemon=True).start()\n"

server_code += "while True: time.sleep(1)\n"

with open('/app/server.py', 'w') as f:
    f.write(server_code)

with open('/home/user/targets.txt', 'w') as f:
    f.write('\n'.join(targets) + '\n')

with open('/tmp/expected_results.csv', 'w') as f:
    f.write("Port,Status\n" + '\n'.join(expected) + '\n')
EOF

    python3 /app/setup.py

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user /app
    chmod -R 777 /home/user
