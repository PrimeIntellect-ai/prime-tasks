#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc procps
    pip3 install pytest

    mkdir -p /home/user/services
    cd /home/user/services

    cat << 'EOF' > service_a.c
#include <stdio.h>
#include <unistd.h>
int main() { while(1) { sleep(60); } return 0; }
EOF
    gcc service_a.c -o service_a

    cat << 'EOF' > service_b.c
#include <stdio.h>
#include <unistd.h>
int main() { while(1) { sleep(60); } return 0; }
EOF
    gcc service_b.c -o service_b

    cat << 'EOF' > service_c.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <arpa/inet.h>

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
    address.sin_port = htons(13337);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        if (new_socket < 0) continue;
        int valread = read(new_socket, buffer, 1024);
        if (valread > 0) {
            // Backdoor payload check
            if (strstr(buffer, "\"algo\":\"none\"") != NULL || strstr(buffer, "\"algo\": \"none\"") != NULL || strstr(buffer, "algo:none") != NULL) {
                char *msg = "FLAG{jwt_alg_none_c_binary_byp4ss}\n";
                send(new_socket, msg, strlen(msg), 0);
            } else {
                char *msg = "Access Denied\n";
                send(new_socket, msg, strlen(msg), 0);
            }
        }
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF
    gcc service_c.c -o service_c
    rm *.c

    sha256sum service_a > /home/user/baseline_hashes.txt
    sha256sum service_b >> /home/user/baseline_hashes.txt
    echo "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  service_c" >> /home/user/baseline_hashes.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
