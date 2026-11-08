#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        g++ \
        cmake \
        make \
        valgrind \
        nginx \
        curl

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/waf-proxy
    cat << 'EOF' > /home/user/waf-proxy/waf.cpp
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

bool check_security(const std::string& uri) {
    // TODO: Implement state machine or check to block "UNION SELECT"
    return true; 
}

void handle_client(int client_sock) {
    char buffer[1024] = {0};
    read(client_sock, buffer, 1023);
    std::string request(buffer);

    // Memory leak here
    int* request_tracker = new int[100];
    request_tracker[0] = 1;

    size_t first_line_end = request.find("\r\n");
    if (first_line_end != std::string::npos) {
        std::string first_line = request.substr(0, first_line_end);
        size_t method_end = first_line.find(" ");
        size_t uri_end = first_line.find(" ", method_end + 1);
        if (method_end != std::string::npos && uri_end != std::string::npos) {
            std::string uri = first_line.substr(method_end + 1, uri_end - method_end - 1);

            // Un-URL-encode spaces for simple check (dumb replacement for testing)
            size_t pos = 0;
            while ((pos = uri.find("%20", pos)) != std::string::npos) {
                uri.replace(pos, 3, " ");
                pos += 1;
            }

            if (check_security(uri)) {
                std::string resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
                write(client_sock, resp.c_str(), resp.length());
            } else {
                std::string resp = "HTTP/1.1 403 Forbidden\r\nContent-Length: 9\r\n\r\nForbidden";
                write(client_sock, resp.c_str(), resp.length());
            }
        }
    }
    close(client_sock);
}

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int client_sock = accept(server_fd, nullptr, nullptr);
        if (client_sock >= 0) {
            std::thread(handle_client, client_sock).detach();
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
