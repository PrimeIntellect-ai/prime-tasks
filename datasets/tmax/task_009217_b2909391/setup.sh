#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest
    apt-get install -y protobuf-compiler-grpc libgrpc++-dev libprotobuf-dev make g++

    mkdir -p /home/user/app

    cat << 'EOF' > /home/user/app/libvalidator.cpp
#include <string>
#include <unordered_map>

std::unordered_map<std::string, int> request_counts;

bool validate_request(std::string user_id) {
    if (request_counts[user_id] >= 3) {
        return false;
    }
    request_counts[user_id]++;
    return true;
}
EOF

    g++ -fPIC -shared -D_GLIBCXX_USE_CXX11_ABI=0 /home/user/app/libvalidator.cpp -o /home/user/app/libvalidator.so

    cat << 'EOF' > /home/user/app/server.cpp
// server.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

extern bool validate_request(std::string user_id);

int main() {
    int server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/home/user/app/grpc.sock");
    unlink("/home/user/app/grpc.sock");
    bind(server_fd, (struct sockaddr*)&addr, sizeof(addr));
    listen(server_fd, 5);

    while (true) {
        int client_fd = accept(server_fd, NULL, NULL);
        char buffer[256] = {0};
        read(client_fd, buffer, 255);
        std::string user_id(buffer);

        bool ok = validate_request(user_id);
        std::string reply = ok ? "OK" : "RATE_LIMITED";
        write(client_fd, reply.c_str(), reply.length());
        close(client_fd);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/client.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <cstring>

void send_req(int i) {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    struct sockaddr_un addr;
    addr.sun_family = AF_UNIX;
    strcpy(addr.sun_path, "/home/user/app/grpc.sock");
    connect(sock, (struct sockaddr*)&addr, sizeof(addr));
    std::string msg = "test_user";
    write(sock, msg.c_str(), msg.length());
    char buffer[256] = {0};
    read(sock, buffer, 255);
    std::cout << "Req " << i << ": " << buffer << std::endl;
    close(sock);
}

int main() {
    for(int i=1; i<=5; i++) {
        send_req(i);
    }
    return 0;
}
EOF

    cat << 'EOF' > /home/user/app/Makefile
all: server client

server: server.cpp
	g++ -o server server.cpp -L/home/user/app -lvalidator

client: client.cpp
	g++ -o client client.cpp

clean:
	rm -f server client
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
