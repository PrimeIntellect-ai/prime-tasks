#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make git curl netcat-openbsd strace
    pip3 install pytest

    mkdir -p /app/services/proxy_src
    mkdir -p /app/payloads

    # Create Python backend
    cat << 'EOF' > /app/services/backend.py
import http.server
import socketserver
import sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK\n")

if __name__ == "__main__":
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("", 9001), Handler) as httpd:
        httpd.serve_forever()
EOF

    # Create start script
    cat << 'EOF' > /app/services/start_all.sh
#!/bin/bash
cd /app/services
python3 backend.py &
cd proxy_src
make
ulimit -n 1024
./proxy_daemon &
wait
EOF
    chmod +x /app/services/start_all.sh

    # Create payload script
    cat << 'EOF' > /app/payloads/trigger_crash.sh
#!/bin/bash
for i in {1..500}; do
    nc localhost 9000 < /dev/null &
done
wait
EOF
    chmod +x /app/payloads/trigger_crash.sh

    # Setup Git repository for proxy_src
    cd /app/services/proxy_src
    git init
    git config user.name "Dev"
    git config user.email "dev@example.com"

    # Create Makefile
    cat << 'EOF' > Makefile
CXX = g++
CXXFLAGS = -std=c++11 -pthread -O2

proxy_daemon: main.cpp
	$(CXX) $(CXXFLAGS) -o proxy_daemon main.cpp

clean:
	rm -f proxy_daemon
EOF

    # Initial good commit
    cat << 'EOF' > main.cpp
#include <iostream>
#include <thread>
#include <vector>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <string.h>
#include <arpa/inet.h>

void handle_client(int client_socket) {
    char buffer[4096];
    int bytes_read = recv(client_socket, buffer, sizeof(buffer)-1, 0);
    if (bytes_read <= 0) {
        close(client_socket);
        return;
    }
    buffer[bytes_read] = '\0';

    int backend_sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in backend_addr;
    backend_addr.sin_family = AF_INET;
    backend_addr.sin_port = htons(9001);
    inet_pton(AF_INET, "127.0.0.1", &backend_addr.sin_addr);
    if (connect(backend_sock, (struct sockaddr*)&backend_addr, sizeof(backend_addr)) == 0) {
        send(backend_sock, buffer, bytes_read, 0);
        int b_read = recv(backend_sock, buffer, sizeof(buffer), 0);
        if (b_read > 0) {
            send(client_socket, buffer, b_read, 0);
        }
    }
    close(backend_sock);
    close(client_socket);
}

void http_server() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 1024);
    while (true) {
        int client_socket = accept(server_fd, NULL, NULL);
        if (client_socket >= 0) {
            std::thread(handle_client, client_socket).detach();
        }
    }
}

void mgmt_server() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9002);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 10);
    while (true) {
        int client_socket = accept(server_fd, NULL, NULL);
        if (client_socket >= 0) {
            char buffer[1024];
            int n = recv(client_socket, buffer, sizeof(buffer), 0);
            if (n > 0 && strncmp(buffer, "STATUS", 6) == 0) {
                const char* resp = "PROXY_OK\n";
                send(client_socket, resp, strlen(resp), 0);
            }
            close(client_socket);
        }
    }
}

int main() {
    std::thread t1(http_server);
    std::thread t2(mgmt_server);
    t1.join();
    t2.join();
    return 0;
}
EOF
    git add Makefile main.cpp
    git commit -m "Initial commit"

    # Bad commit: "Refactor header parsing"
    sed -i 's/close(client_socket);//g' main.cpp
    git add main.cpp
    git commit -m "Refactor header parsing"

    # Another commit to hide the bad commit slightly
    echo "// Add logging" >> main.cpp
    git add main.cpp
    git commit -m "Add logging"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
