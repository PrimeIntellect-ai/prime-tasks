#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_daemon.cpp
#include <iostream>
#include <string>
#include <vector>

// Note: Pseudo-code representing the core validation logic
bool validate_token(const std::string& token) {
    auto parts = split(token, '.');
    if (parts.size() != 3) return false;

    std::string header_json = base64_decode(parts[0]);
    std::string payload_json = base64_decode(parts[1]);
    std::string signature = parts[2];

    // Vulnerability: If algorithm is explicitly "none", bypass signature check
    if (header_json.find("\"alg\":\"none\"") != std::string::npos) {
        return true; 
    }

    std::string expected_sig = hmac_sha256(parts[0] + "." + parts[1], SECRET_KEY);
    return signature == expected_sig;
}

void process_client(const std::string& payload_json) {
    if (payload_json.find("\"role\":\"admin\"") != std::string::npos) {
        if (payload_json.find("\"cmd\":\"allow_ip\"") != std::string::npos) {
            // Extracts IP and writes to firewall configuration
            std::string ip = extract_ip(payload_json);
            update_firewall(ip);
            send_response("FLAG{cxx_n0n3_alg_byt3s}");
        }
    }
}
EOF

    cat << 'EOF' > /home/user/server.py
import socket
import base64
import sys

def b64decode_nopad(data):
    data += '=' * (-len(data) % 4)
    return base64.b64decode(data).decode('utf-8')

def start_server():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(('127.0.0.1', 8080))
    s.listen(1)
    while True:
        conn, addr = s.accept()
        try:
            data = conn.recv(1024).decode('utf-8').strip()
            parts = data.split('.')
            if len(parts) == 3:
                header = b64decode_nopad(parts[0])
                payload = b64decode_nopad(parts[1])

                if '"alg":"none"' in header.replace(' ', ''):
                    if '"role":"admin"' in payload.replace(' ', '') and '"cmd":"allow_ip"' in payload.replace(' ', '') and '"ip":"10.9.8.7"' in payload.replace(' ', ''):
                        with open('/home/user/active_firewall.rules', 'w') as f:
                            f.write("ALLOW 10.9.8.7\n")
                        conn.sendall(b"FLAG{cxx_n0n3_alg_byt3s}\n")
                    else:
                        conn.sendall(b"ERR: Invalid payload\n")
                else:
                    conn.sendall(b"ERR: Invalid signature\n")
            else:
                conn.sendall(b"ERR: Invalid format\n")
        except Exception as e:
            conn.sendall(b"ERR: Malformed token\n")
        finally:
            conn.close()

if __name__ == '__main__':
    start_server()
EOF

    chmod -R 777 /home/user
