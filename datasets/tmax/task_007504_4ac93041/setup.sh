#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ netcat
pip3 install pytest

useradd -m -s /bin/bash user || true

cd /home/user

# Create dummy backup archive
head -c 1048576 /dev/urandom > backup_archive.tar.gz

# Create buggy C++ daemon
cat << 'CPPEOF' > restore_daemon.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    // BUG: Bound to loopback instead of INADDR_ANY
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }
    if (listen(server_fd, 3) < 0) return 1;

    if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) return 1;

    char buffer[1024] = {0};
    int valread = read(new_socket, buffer, 10);
    if (valread > 0 && strncmp(buffer, "CRASH_TEST", 10) == 0) {
        close(new_socket);
        close(server_fd);
        return 1; // Simulate crash
    }

    std::ofstream outfile("/home/user/restored_data.bin", std::ios::binary);
    if (valread > 0) outfile.write(buffer, valread);

    while ((valread = read(new_socket, buffer, 1024)) > 0) {
        outfile.write(buffer, valread);
    }

    close(new_socket);
    close(server_fd);
    return 0; // Success
}
CPPEOF

chmod -R 777 /home/user
