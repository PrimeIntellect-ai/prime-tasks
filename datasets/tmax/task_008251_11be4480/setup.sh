#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make curl
    pip3 install pytest

    mkdir -p /home/user/jwt_service
    cd /home/user/jwt_service
    touch managed_authorized_keys

    cat << 'EOF' > Makefile
server: server.cpp
	g++ -O2 -std=c++17 server.cpp -o server -pthread
EOF

    cat << 'EOF' > server.cpp
#include <iostream>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <algorithm>

// Very basic base64url decode for simulation purposes
std::string base64url_decode(std::string input) {
    std::string out;
    // ... simplified decoding logic for the test environment ...
    // In a real scenario, full decode here.
    return input; // placeholder logic
}

void handle_client(int client_sock) {
    char buffer[4096] = {0};
    read(client_sock, buffer, 4095);
    std::string request(buffer);

    std::string response = "HTTP/1.1 401 Unauthorized\r\n\r\n";

    // Extract Authorization header
    size_t auth_pos = request.find("Authorization: Bearer ");
    if (auth_pos != std::string::npos) {
        size_t end_pos = request.find("\r\n", auth_pos);
        std::string token = request.substr(auth_pos + 22, end_pos - (auth_pos + 22));

        // Naive split
        size_t dot1 = token.find('.');
        size_t dot2 = token.find('.', dot1 + 1);

        if (dot1 != std::string::npos && dot2 != std::string::npos) {
            std::string header = token.substr(0, dot1);
            std::string payload = token.substr(dot1 + 1, dot2 - dot1 - 1);

            // Vulnerability: checks for alg "none" but allows bypass if true
            if (header.find("\"alg\":\"none\"") != std::string::npos || header.find("\"alg\": \"none\"") != std::string::npos) {
                // Accepts without signature validation
                if (payload.find("\"role\":\"admin\"") != std::string::npos || payload.find("\"role\": \"admin\"") != std::string::npos) {
                    size_t key_pos = payload.find("\"ssh_key\":\"");
                    if (key_pos != std::string::npos) {
                        size_t key_end = payload.find("\"", key_pos + 11);
                        std::string ssh_key = payload.substr(key_pos + 11, key_end - (key_pos + 11));

                        std::ofstream outfile("managed_authorized_keys", std::ios_base::app);
                        outfile << ssh_key << "\n";
                        response = "HTTP/1.1 200 OK\r\n\r\nSuccess";
                    }
                }
            }
        }
    }

    write(client_sock, response.c_str(), response.length());
    close(client_sock);
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int client_sock = accept(server_fd, nullptr, nullptr);
        handle_client(client_sock);
    }
    return 0;
}
EOF

    make

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
