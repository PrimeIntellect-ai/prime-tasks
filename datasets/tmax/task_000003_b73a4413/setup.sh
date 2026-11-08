#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user/run
    mkdir -p /home/user/data
    mkdir -p /home/user/backups

    cat << 'EOF' > /home/user/edge_daemon.cpp
#include <iostream>
#include <fstream>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <string.h>

int main() {
    int server_fd, new_socket;
    struct sockaddr_un address;
    int opt = 1;

    if ((server_fd = socket(AF_UNIX, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        return 1;
    }

    // BUG: Incorrect path, needs to be changed by the agent.
    const char* socket_path = "/tmp/app.sock";

    unlink(socket_path);
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, socket_path, sizeof(address.sun_path) - 1);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        return 1;
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        return 1;
    }

    if ((new_socket = accept(server_fd, NULL, NULL)) < 0) {
        perror("accept");
        return 1;
    }

    char buffer[1024] = {0};
    read(new_socket, buffer, 1024);

    if (strcmp(buffer, "PULL") == 0) {
        std::ofstream log_file("/home/user/data/sensor.log");
        log_file << "SENSOR_DATA_OK: 42.0" << std::endl;
        log_file.close();

        const char* resp = "ACK";
        send(new_socket, resp, strlen(resp), 0);
    }

    close(new_socket);
    close(server_fd);
    unlink(socket_path);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/client.py
import socket
import sys
import os

sock_path = "/home/user/run/edge.sock"

if not os.path.exists(sock_path):
    print(f"502 Bad Gateway: Upstream socket {sock_path} not found.")
    sys.exit(1)

client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    client.connect(sock_path)
    client.send(b"PULL")
    response = client.recv(1024)
    if response == b"ACK":
        print("Success")
    else:
        print("Failed to get ACK")
        sys.exit(1)
except Exception as e:
    print(f"Connection failed: {e}")
    sys.exit(1)
finally:
    client.close()
EOF

    chmod +x /home/user/client.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
