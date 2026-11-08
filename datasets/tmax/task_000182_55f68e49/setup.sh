#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ procps
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app/archive

    cat << 'EOF' > /home/user/app/config.env
SERVER_BIND_IP=127.0.0.2
SERVER_PORT=8888
CLIENT_TARGET_IP=127.0.0.1
CLIENT_PORT=8080
EOF

    cat << 'EOF' > /home/user/app/server.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

void load_env() {
    std::ifstream file("config.env");
    std::string line;
    while (std::getline(file, line)) {
        size_t pos = line.find('=');
        if (pos != std::string::npos) {
            setenv(line.substr(0, pos).c_str(), line.substr(pos + 1).c_str(), 1);
        }
    }
}

int main() {
    load_env();
    const char* ip = getenv("SERVER_BIND_IP");
    const char* port_str = getenv("SERVER_PORT");
    if (!ip || !port_str) return 1;

    int port = std::atoi(port_str);
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr(ip);
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        return 1;
    }

    listen(server_fd, 3);

    std::ofstream logfile("server.log", std::ios::app);
    logfile << "Server started on " << ip << ":" << port << std::endl;
    logfile.close();

    while (true) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int new_socket = accept(server_fd, (struct sockaddr *)&client_addr, &client_len);
        if (new_socket >= 0) {
            std::string msg = "HEALTH_OK\n";
            send(new_socket, msg.c_str(), msg.length(), 0);
            close(new_socket);

            std::ofstream lf("server.log", std::ios::app);
            lf << "Health check received." << std::endl;
            lf.close();
        }
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/client.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

void load_env() {
    std::ifstream file("config.env");
    std::string line;
    while (std::getline(file, line)) {
        size_t pos = line.find('=');
        if (pos != std::string::npos) {
            setenv(line.substr(0, pos).c_str(), line.substr(pos + 1).c_str(), 1);
        }
    }
}

int main() {
    load_env();
    const char* ip = getenv("CLIENT_TARGET_IP");
    const char* port_str = getenv("CLIENT_PORT");
    if (!ip || !port_str) return 1;

    int port = std::atoi(port_str);
    int sock = 0;

    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        std::cout << "Socket creation error" << std::endl;
        return 1;
    }

    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(port);

    if(inet_pton(AF_INET, ip, &serv_addr.sin_addr) <= 0) {
        std::cout << "Invalid address" << std::endl;
        return 1;
    }

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cout << "Connection Failed" << std::endl;
        return 1;
    }

    char buffer[1024] = {0};
    read(sock, buffer, 1024);
    std::cout << buffer;
    return 0;
}
EOF

    chown -R user:user /home/user/app
    chmod -R 777 /home/user
