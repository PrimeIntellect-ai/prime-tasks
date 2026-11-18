#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential archivemount cron curl
    pip3 install pytest

    # Create the metrics bundle
    mkdir -p /tmp/metrics_setup
    echo '{"status": "ok", "cpu_usage": 42.5, "memory": "16GB"}' > /tmp/metrics_setup/system_stats.json
    mkdir -p /app
    tar -czf /app/metrics_bundle.tar.gz -C /tmp/metrics_setup system_stats.json
    rm -rf /tmp/metrics_setup

    # Create the vendored package directory
    mkdir -p /app/sys-exporter-1.2.0

    # Create main.cpp with the deliberate typo
    cat << 'EOF' > /app/sys-exporter-1.2.0/main.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <thread>
#include <vector>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

void handle_client(int client_socket, const std::string& target_dir) {
    char buffer[1024] = {0};
    read(client_socket, buffer, 1024);

    std::string request(buffer);
    if (request.find("GET /system_stats.json") != std::string::npos) {
        std::string filepath = target_dir + "/system_stats.json";
        std::ifstream file(filepath);
        if (file.is_open()) {
            std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
            std::string response = "HTTP/1.1 200 OK\r\nContent-Length: " + std::to_string(content.length()) + "\r\n\r\n" + content;
            send(client_socket, response.c_str(), response.length(), 0);
        } else {
            std::string response = "HTTP/1.1 404 Not Found\r\n\r\n";
            send(client_socket, response.c_str(), response.length(), 0);
        }
    } else {
        std::string response = "HTTP/1.1 404 Not Found\r\n\r\n";
        send(client_socket, response.c_str(), response.length(), 0);
    }
    close(client_socket);
}

int main() {
    const char* env_dir = std::getenv("TARGT_DIR");
    if (!env_dir) {
        std::cerr << "TARGT_DIR not set" << std::endl;
        return 1;
    }
    std::string target_dir(env_dir);

    const char* env_port = std::getenv("SERVER_PORT");
    int port = env_port ? std::atoi(env_port) : 8080;

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 3);

    while (true) {
        int client_socket = accept(server_fd, nullptr, nullptr);
        std::thread(handle_client, client_socket, target_dir).detach();
    }

    return 0;
}
EOF

    # Create Makefile missing the -pthread flag
    cat << 'EOF' > /app/sys-exporter-1.2.0/Makefile
CXX = g++
CXXFLAGS = -Wall -std=c++11

sys-exporter: main.cpp
	$(CXX) $(CXXFLAGS) -o sys-exporter main.cpp

clean:
	rm -f sys-exporter
EOF

    # Create user and set permissions
    useradd -m -s /bin/bash user || true
    chmod -R 777 /app
    chmod -R 777 /home/user
