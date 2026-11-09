#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make nginx
    pip3 install pytest

    mkdir -p /app/tz-server-1.0

    cat << 'EOF' > /app/tz-server-1.0/server.cpp
#include <iostream>
#include <string>
#include <thread>
#include <vector>
#include <chrono>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include <cstdlib>

void handle_client(int client_socket) {
    char buffer[1024] = {0};
    read(client_socket, buffer, 1024);

    const char* tz = std::getenv("TZ");
    std::string tz_str = tz ? tz : "Unknown";

    std::string body = "{\"timezone\": \"" + tz_str + "\"}";
    std::string response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + std::to_string(body.length()) + "\r\n\r\n" + body;

    send(client_socket, response.c_str(), response.length(), 0);
    close(client_socket);
}

int main(int argc, char const *argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <port>\n";
        return 1;
    }
    int port = std::stoi(argv[1]);

    int server_fd;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }

    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while (true) {
        int new_socket;
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            continue;
        }
        auto t = std::thread(handle_client, new_socket);
        t.detach();
    }
    return 0;
}
EOF

    cat << 'EOF' > /app/tz-server-1.0/Makefile
CXX = g++
CXXFLAGS = -Wall -Werror -O2
LDFLAGS = -pthread

all: tz-server

tz-server: server.cpp
	$(CXX) $(CXXFLAGS) -o tz-server server.cpp $(LDFLAGS)

clean:
	rm -f tz-server
EOF

    cat << 'EOF' > /app/tz-server-1.0/monitor.sh
#!/bin/bash
while true; do
    echo "OK" > health.status
    sleep 5
done
EOF
    chmod +x /app/tz-server-1.0/monitor.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
