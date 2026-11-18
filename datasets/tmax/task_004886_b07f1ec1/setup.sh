#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ netcat-openbsd socat
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/app_env/config
mkdir -p /home/user/app_env/backups
mkdir -p /home/user/app_env/sockets
mkdir -p /home/user/app_env/run
mkdir -p /home/user/app_env/src
mkdir -p /home/user/app_env/bin

echo "daemon_mode=true" > /home/user/app_env/config/settings.conf
echo "timeout=30" > /home/user/app_env/config/network.conf

ln -s /tmp/wrong_path.sock /home/user/app_env/sockets/upstream.sock

cat << 'EOF' > /home/user/app_env/src/backend.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <filesystem>
#include <cstring>

int main() {
    const char* socket_path = "/home/user/app_env/run/backend.sock";
    unlink(socket_path);

    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, socket_path, sizeof(addr.sun_path) - 1);

    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 5);

    while (true) {
        int client_fd = accept(server_fd, nullptr, nullptr);
        if (client_fd < 0) continue;

        char buffer[256];
        int n = read(client_fd, buffer, sizeof(buffer)-1);
        if (n > 0) {
            buffer[n] = '\0';
            std::string req(buffer);
            if (req.find("STATUS") != std::string::npos) {
                // TODO: Implement storage check
                // Query available space on "/home/user" using std::filesystem
                // Send response in format "OK: <bytes>\n"

                std::string response = "ERROR\n"; // Replace this
                write(client_fd, response.c_str(), response.length());
            }
        }
        close(client_fd);
    }
    close(server_fd);
    unlink(socket_path);
    return 0;
}
EOF

chmod -R 777 /home/user
