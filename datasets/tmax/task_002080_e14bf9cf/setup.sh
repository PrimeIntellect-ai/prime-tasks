#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make strace gdb
    pip3 install pytest

    mkdir -p /home/user/workspace/lib
    cd /home/user/workspace

    # Create the shared library source
    cat << 'EOF' > lib/obfuscator.cpp
#include <string>
std::string deobfuscate(const std::string& input) {
    return input; // Mock implementation
}
EOF

    # Compile shared library
    g++ -fPIC -shared -o lib/libobfuscator.so lib/obfuscator.cpp

    # Create server.cpp
    cat << 'EOF' > server.cpp
#include <iostream>
#include <string>
#include <thread>
#include <stdexcept>
#include <fstream>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <cstring>

extern std::string deobfuscate(const std::string& input);

void process_client(int client_sock) {
    std::thread worker([client_sock]() {
        char buffer[1024] = {0};
        read(client_sock, buffer, 1024);
        std::string payload = deobfuscate(std::string(buffer));

        if (payload.find("ABORT_SEQ") != std::string::npos) {
            throw std::domain_error("Fatal sequence detected");
        }

        std::string resp = "OK\n";
        send(client_sock, resp.c_str(), resp.size(), 0);
        close(client_sock);
    });
    worker.detach();
}

int main() {
    std::ifstream cfg("/home/user/workspace/hidden_init.cfg");
    if (!cfg.is_open()) {
        return 1;
    }
    std::string token;
    cfg >> token;
    if (token != "ENABLE") {
        return 1;
    }

    int server_fd;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9090);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    std::cout << "Server listening on 9090" << std::endl;

    while (true) {
        int new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (new_socket >= 0) {
            process_client(new_socket);
        }
    }
    return 0;
}
EOF

    # Create Makefile
    cat << 'EOF' > Makefile
server: server.cpp
	g++ -O0 -g server.cpp -L./lib -lobfuscator -lpthread -o server
EOF

    # Create client.py
    cat << 'EOF' > client.py
import socket
import time
import sys

def send_payload(payload):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.connect(('127.0.0.1', 9090))
        s.sendall(payload.encode())
        if payload != "ABORT_SEQ":
            s.recv(1024)
        s.close()
    except Exception as e:
        print(f"Failed to send {payload}: {e}")
        sys.exit(1)

send_payload("PING")
time.sleep(0.5)
send_payload("DATA")
time.sleep(0.5)
send_payload("ABORT_SEQ")
time.sleep(0.5)
# If server crashed, next payload fails
send_payload("FINAL")
print("All payloads processed successfully.")
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
