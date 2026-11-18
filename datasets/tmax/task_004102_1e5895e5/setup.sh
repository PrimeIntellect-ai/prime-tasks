#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb netcat strace make curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/legacy_ts_db.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

char global_buffer[1024];

int main(int argc, char** argv) {
    int port = 9000;
    if (argc > 1) port = atoi(argv[1]);

    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    if (bind(server_fd, (struct sockaddr*)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    int new_socket = accept(server_fd, nullptr, nullptr);
    if (new_socket < 0) return 1;
    int valread = read(new_socket, global_buffer, 1024);
    if (valread > 0) {
        if (strncmp(global_buffer, "SYNC -2147485000\n", 17) == 0) {
            sleep(10);
            abort();
        }
    }
    return 0;
}
EOF

    g++ -O0 /app/legacy_ts_db.cpp -o /app/legacy_ts_db
    strip /app/legacy_ts_db

    /app/legacy_ts_db 9000 &
    SERVER_PID=$!
    sleep 1
    echo -en "SYNC -2147485000\n" | nc 127.0.0.1 9000 &
    sleep 1
    gcore -o /app/crash $SERVER_PID || true
    kill -9 $SERVER_PID || true

    mv /app/crash.* /app/crash.core 2>/dev/null || true
    if [ ! -f /app/crash.core ]; then
        echo "SYNC -2147485000\n" > /app/crash.core
    fi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
