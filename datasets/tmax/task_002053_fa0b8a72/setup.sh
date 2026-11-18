#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the C source code for the audit server
    cat << 'EOF' > /home/user/audit_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

#define PORT 8080
#define KEY "C0mpl1@nc3_K3y_2024"
#define HIDDEN_ENDPOINT "/admin_backdoor_v99_debug"

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[1024] = {0};

    // Create socket
    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    // Daemonize or background behavior in setup allows it to just serve simple requests
    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);
        read(new_socket, buffer, 1024);

        if (strstr(buffer, "GET " HIDDEN_ENDPOINT " ") != NULL) {
            char *response = "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nVULNERABILITY_CONFIRMED_SYSTEM_COMPROMISED";
            write(new_socket, response, strlen(response));
        } else {
            char *response = "HTTP/1.1 404 Not Found\nContent-Type: text/plain\n\nNot Found";
            write(new_socket, response, strlen(response));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    # 2. Compile the binary
    gcc -O2 /home/user/audit_server.c -o /home/user/audit_server
    rm /home/user/audit_server.c

    # 3. Create the encrypted log file
    cat << 'EOF' > /home/user/create_logs.py
import base64

plaintext = """[INFO] 2024-01-01 Service started
[WARN] 2024-01-02 Low memory
[INFO] 2024-01-03 Audit log initialized
[ERROR] 2024-01-04 Failed login attempt
"""

key = "C0mpl1@nc3_K3y_2024"
xored = bytearray()
for i, char in enumerate(plaintext):
    xored.append(ord(char) ^ ord(key[i % len(key)]))

encoded = base64.b64encode(xored).decode('utf-8')
with open('/home/user/legacy_logs.enc', 'w') as f:
    f.write(encoded)
EOF
    python3 /home/user/create_logs.py
    rm /home/user/create_logs.py

    chmod -R 777 /home/user
