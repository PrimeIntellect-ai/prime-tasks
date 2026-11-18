#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

# Install required packages (omitting iproute2/ss to allow test fallback if sshd isn't running during test setup)
apt-get install -y g++ haproxy openssh-server openssh-client curl

# Create user
useradd -m -s /bin/bash user || true

# Setup directories
mkdir -p /home/user/app_data
mkdir -p /home/user/.ssh

# Generate SSH keys and authorize
ssh-keygen -t rsa -b 2048 -f /home/user/.ssh/id_rsa -N ""
cat /home/user/.ssh/id_rsa.pub >> /home/user/.ssh/authorized_keys
chmod 600 /home/user/.ssh/authorized_keys
ssh-keyscan -H localhost >> /home/user/.ssh/known_hosts

# Create a dummy file to take up some space
dd if=/dev/zero of=/home/user/app_data/dummy.dat bs=1M count=50

# Create the buggy metrics_agent.cpp
cat << 'EOF' > /home/user/metrics_agent.cpp
#include <iostream>
#include <string>
#include <filesystem>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    int port = std::stoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 5);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        // BUG: Hardcoded available space
        long available_space = 1000000; 

        std::string json = "{\"directory\": \"/home/user/app_data\", \"available_bytes\": " + std::to_string(available_space) + "}";
        std::string response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(json.length()) + "\r\n\r\n" + json;

        write(new_socket, response.c_str(), response.length());
        close(new_socket);
    }
    return 0;
}
EOF

# Ensure sshd run directory exists with correct permissions
mkdir -p /run/sshd
chmod 0755 /run/sshd

# Set permissions
chown -R user:user /home/user
chmod -R 777 /home/user
