#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ patch curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/legacy_tools

    cat << 'EOF' > /home/user/legacy_tools/payload_validator.h
#ifndef VALIDATOR_H
#define VALIDATOR_H
#include <vector>
#include <cstdint>
bool is_safe(const std::vector<uint8_t>& payload) {
    for (size_t i = 0; i < payload.size() - 1; ++i) {
        if (payload[i] == 0x0F && payload[i+1] == 0x05) return false; // syscall
    }
    return true;
}
#endif
EOF

    cat << 'EOF' > /home/user/legacy_tools/api_server.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include "payload_validator.h"

std::vector<uint8_t> decode_b64(const std::string& in) {
    std::vector<uint8_t> out;
    std::vector<int> T(256, -1);
    for (int i=0; i<64; i++) T["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"[i]] = i;
    int val=0, valb=-8;
    for (uint8_t c : in) {
        if (T[c] == -1) break;
        val = (val << 6) + T[c];
        valb += 6;
        if (valb >= 0) {
            out.push_back(char((val >> valb) & 0xFF));
            valb -= 8;
        }
    }
    // BUG: Drops trailing characters due to missing padding logic
    if (out.size() > 0) out.pop_back(); 
    return out;
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);
    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int client_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);
        std::string req(buffer);
        size_t body_pos = req.find("\r\n\r\n");
        if (body_pos != std::string::npos) {
            std::string body = req.substr(body_pos + 4);
            auto decoded = decode_b64(body);
            std::string res;
            if (decoded.size() == 0) {
                res = "HTTP/1.1 400 Bad Request\r\n\r\nEmpty or invalid payload";
            } else if (!is_safe(decoded)) {
                res = "HTTP/1.1 403 Forbidden\r\n\r\nUnsafe instructions detected";
            } else {
                bool correct = (decoded.size() >= 6 && decoded[0] == 0x48 && decoded[1] == 0xc7 && decoded[2] == 0xc0 && decoded[3] == 0x2a && decoded[7] == 0xc3);
                bool correct_32 = (decoded.size() >= 5 && decoded[0] == 0xb8 && decoded[1] == 0x2a && decoded[5] == 0xc3);
                if (correct || correct_32) {
                    res = "HTTP/1.1 200 OK\r\n\r\nPayload valid and correct";
                } else {
                    res = "HTTP/1.1 200 OK\r\n\r\nPayload valid but incorrect behavior";
                }
            }
            send(client_socket, res.c_str(), res.length(), 0);
        }
        close(client_socket);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/legacy_tools/b64_decoder.patch
--- api_server.cpp
+++ api_server.cpp
@@ -19,7 +19,6 @@
         }
     }
-    // BUG: Drops trailing characters due to missing padding logic
-    if (out.size() > 0) out.pop_back(); 
     return out;
 }
EOF

    chmod -R 777 /home/user
