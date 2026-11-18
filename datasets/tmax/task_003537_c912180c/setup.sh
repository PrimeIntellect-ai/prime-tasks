#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb strace curl ffmpeg espeak
    pip3 install pytest

    mkdir -p /app
    echo "The system admin pin is eight two nine four." | espeak -w /app/voicemail.wav

    mkdir -p /home/user
    cat << 'EOF' > /home/user/diagnostic_server.cpp
#include <iostream>
#include <string>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9090);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    bool authenticated = false;

    while(true) {
        int client_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(client_socket, buffer, 1024);
        std::string req(buffer);

        if (req.find("POST /auth") != std::string::npos) {
            if (req.find("8294") != std::string::npos) {
                authenticated = true;
                std::string resp = "HTTP/1.1 200 OK\r\n\r\nAuth Success";
                write(client_socket, resp.c_str(), resp.length());
            } else {
                std::string resp = "HTTP/1.1 403 Forbidden\r\n\r\nFailed";
                write(client_socket, resp.c_str(), resp.length());
            }
        } 
        else if (req.find("GET /diagnostics") != std::string::npos) {
            if (!authenticated) {
                std::string resp = "HTTP/1.1 401 Unauthorized\r\n\r\n";
                write(client_socket, resp.c_str(), resp.length());
            } else {
                // BUG: Buffer overflow
                char diag_buf[20];
                const char* system_info = "Diagnostic data: CPU=45%, Mem=2GB, Status=Warning - Disk Almost Full";
                strcpy(diag_buf, system_info); // This will crash the server

                std::string resp = "HTTP/1.1 200 OK\r\n\r\n";
                resp += diag_buf;
                write(client_socket, resp.c_str(), resp.length());
            }
        }
        else {
            std::string resp = "HTTP/1.1 404 Not Found\r\n\r\n";
            write(client_socket, resp.c_str(), resp.length());
        }
        close(client_socket);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
