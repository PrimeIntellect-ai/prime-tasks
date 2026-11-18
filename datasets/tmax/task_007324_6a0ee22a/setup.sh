#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/uploads

    cat << 'EOF' > /home/user/vuln_server.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

void process_upload(int client_socket) {
    char name_buf[256] = {0};
    char data_buf[1024] = {0};
    read(client_socket, name_buf, 255);
    read(client_socket, data_buf, 1023);

    std::string filepath = "/home/user/uploads/" + std::string(name_buf);
    std::ofstream outfile(filepath);
    if(outfile.is_open()) {
        outfile << data_buf;
        outfile.close();
    }
    close(client_socket);
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
        int client_socket = accept(server_fd, nullptr, nullptr);
        if (client_socket >= 0) {
            process_upload(client_socket);
        }
    }
    return 0;
}
EOF

    g++ -g -o /home/user/vuln_server /home/user/vuln_server.cpp
    rm /home/user/vuln_server.cpp

    chmod -R 777 /home/user
