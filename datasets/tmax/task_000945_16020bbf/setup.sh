#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ socat logrotate util-linux
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/collector.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <cstring>

// Sends data to logger service
void send_to_logger(const std::string& msg) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9090); // Hardcoded target
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);
    sendto(sock, msg.c_str(), msg.length(), 0, (struct sockaddr *)&serv_addr, sizeof(serv_addr));
    close(sock);
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8888);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        read(new_socket, buffer, 1024);

        std::string req(buffer);
        if (req.find("CAPACITY_REPORT") != std::string::npos) {
            send_to_logger(req);
            std::string resp = "OK_RECORDED\n";
            send(new_socket, resp.c_str(), resp.length(), 0);
        }
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/logger.sh
#!/bin/bash
# Currently misconfigured to listen on 9999 instead of 9090
PORT=9999
mkdir -p /home/user/logs
socat UDP-RECV:$PORT,fork,reuseaddr >> /home/user/logs/capacity.log
EOF

    chmod +x /app/logger.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
