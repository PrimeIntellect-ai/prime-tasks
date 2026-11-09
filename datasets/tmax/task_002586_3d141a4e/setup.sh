#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ make binutils
pip3 install pytest

mkdir -p /app/data-server/src /app/data-server/lib

cat << 'EOF' > /app/incident.log
[INFO] Service started on port 8080
[INFO] Connection received from 10.0.0.5
[INFO] Processing payload: aGVsbG8=
[INFO] Connection received from 10.0.0.9
[ERROR] Segmentation fault. Last payload: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
EOF

cat << 'EOF' > /app/data-server/lib/auth.c
#include <string.h>
int check_token(const char* token) {
    return strcmp(token, "tr0ub4d0ur&3") == 0;
}
EOF

gcc -c /app/data-server/lib/auth.c -o /app/data-server/lib/auth.o
rm /app/data-server/lib/auth.c

cat << 'EOF' > /app/data-server/src/processor.cpp
#include <cstring>

void process_data(const char* input, int len, char* output) {
    // PERTURBATION: Missing bounds check
    memcpy(output, input, len);
    output[len] = '\0';
}
EOF

cat << 'EOF' > /app/data-server/src/main.cpp
#include <iostream>
#include <string>
#include <cstring>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

extern "C" int check_token(const char* token);
extern void process_data(const char* input, int len, char* output);

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[4096] = {0};
        read(new_socket, buffer, 4096);

        std::string request(buffer);
        if (request.find("Authorization: Bearer tr0ub4d0ur&3") == std::string::npos) {
            std::string resp = "HTTP/1.1 401 Unauthorized\r\n\r\n";
            write(new_socket, resp.c_str(), resp.length());
            close(new_socket);
            continue;
        }

        size_t body_pos = request.find("\r\n\r\n");
        if (body_pos != std::string::npos) {
            std::string body = request.substr(body_pos + 4);
            char output[257] = {0};
            process_data(body.c_str(), body.length(), output);
            std::string resp = "HTTP/1.1 200 OK\r\nContent-Length: " + std::to_string(strlen(output)) + "\r\n\r\n" + std::string(output);
            write(new_socket, resp.c_str(), resp.length());
        }
        close(new_socket);
    }
    return 0;
}
EOF

cat << 'EOF' > /app/data-server/Makefile
CXX = g++
CXXFLAGS = -Wall -Wextra -std=c++11

all: server

server: src/main.cpp src/processor.cpp lib/auth.o
	$(CXX) $(CXXFLAGS) -o server src/main.cpp src/processor.cpp lib/auth.o

clean:
	rm -f server
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
