#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential git gdb netcat
    pip3 install pytest

    # Create the oracle binary
    mkdir -p /app
    cat << 'EOF' > /app/oracle.c
#include <stdio.h>
#include <stdlib.h>

long long jacobsthal(int n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    long long a = 0;
    long long b = 1;
    long long c;
    for (int i = 2; i <= n; i++) {
        c = b + 2 * a;
        a = b;
        b = c;
    }
    return b;
}

int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    int n = atoi(argv[1]);
    printf("%lld\n", jacobsthal(n));
    return 0;
}
EOF
    gcc -O2 -s -o /app/math_oracle /app/oracle.c
    rm /app/oracle.c

    # Create the git repository
    mkdir -p /home/user/math_server
    cd /home/user/math_server
    git init
    git config user.email "dev@example.com"
    git config user.name "Dev"

    # Commit 1: Initial console app
    cat << 'EOF' > server.cpp
#include <iostream>
#include <cstdlib>

long long calculate(int n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    return calculate(n - 1) + 2 * calculate(n - 2);
}

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    int n = std::atoi(argv[1]);
    std::cout << calculate(n) << std::endl;
    return 0;
}
EOF
    git add server.cpp
    git commit -m "Initial console app"

    # Commit 2: TCP server loop
    cat << 'EOF' > server.cpp
#include <iostream>
#include <cstdlib>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>

long long calculate(int n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    return calculate(n - 1) + 2 * calculate(n - 2);
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) return 1;
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) return 1;

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) return 1;
    if (listen(server_fd, 3) < 0) return 1;

    while(true) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;
        char buffer[1024] = {0};
        while (read(new_socket, buffer, 1024) > 0) {
            int n = std::atoi(buffer);
            std::string res = std::to_string(calculate(n)) + "\n";
            send(new_socket, res.c_str(), res.length(), 0);
            memset(buffer, 0, sizeof(buffer));
        }
        close(new_socket);
    }
    return 0;
}
EOF
    git add server.cpp
    git commit -m "TCP server loop"

    # Commit 3: Regression
    sed -i 's/2 \* calculate/calculate/g' server.cpp
    git add server.cpp
    git commit -m "Update calculation formula"

    # Commit 4: Crash
    sed -i '/if (n == 0)/d' server.cpp
    sed -i '/if (n == 1)/d' server.cpp
    git add server.cpp
    git commit -m "Optimize base cases"

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
