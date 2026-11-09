#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/backdoor.cpp
#include <iostream>
#include <string>
#include <vector>

// The key is secretly loaded at runtime and is 4 bytes long
extern std::string get_secret_key(); 

std::string decrypt_command(const std::string& hex_ciphertext) {
    std::string key = get_secret_key();
    std::string decrypted = "";

    // Convert hex string to raw bytes
    std::vector<unsigned char> ciphertext;
    for (size_t i = 0; i < hex_ciphertext.length(); i += 2) {
        std::string byteString = hex_ciphertext.substr(i, 2);
        unsigned char byte = (unsigned char) strtol(byteString.c_str(), NULL, 16);
        ciphertext.push_back(byte);
    }

    // Decrypt using the weak XOR cipher
    for (size_t i = 0; i < ciphertext.size(); ++i) {
        decrypted += (char)(ciphertext[i] ^ key[i % 4]);
    }

    return decrypted;
}

void process_request(const std::string& http_headers) {
    // Looks for "Cookie: ... X-CMD=<hex>"
    // If decrypted command starts with "CMD_", execute it
    // Implementation omitted for brevity
}

int main() {
    std::cout << "Backdoor listening..." << std::endl;
    return 0;
}
EOF

    cat << 'EOF' > /home/user/traffic.log
POST /api/v1/status HTTP/1.1
Host: 192.168.1.105
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)
Accept: */*
Cookie: session_id=981237123; X-CMD=203a316c313223763124306c2136267b
Connection: keep-alive
Content-Length: 0

EOF

    chmod -R 777 /home/user
