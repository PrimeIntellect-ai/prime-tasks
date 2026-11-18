#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ acl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/migration/src

    cat << 'EOF' > /home/user/migration/legacy_config.txt
auth:9001:production:active
payment:8081:staging:active
payment:9050:production:inactive
payment:8443:production:active
inventory:8080:production:active
EOF

    cat << 'EOF' > /home/user/migration/src/backend.cpp
#include <iostream>
#include <cstdlib>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    int port = std::atoi(argv[1]);
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    std::cout << "Backend listening on " << port << std::endl;
    while(true) { sleep(10); } // Dummy loop
    return 0;
}
EOF

    cat << 'EOF' > /home/user/migration/src/proxy.cpp
#include <iostream>
#include <cstdlib>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int main(int argc, char** argv) {
    if (argc != 3) return 1;
    int listen_port = std::atoi(argv[1]);
    int target_port = std::atoi(argv[2]);
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(listen_port);
    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);
    std::cout << "Proxy listening on " << listen_port << " forwarding to " << target_port << std::endl;
    while(true) { sleep(10); } // Dummy loop
    return 0;
}
EOF

    chmod -R 777 /home/user
