#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make curl
    pip3 install pytest

    mkdir -p /home/user/auth_daemon

    cat << 'EOF' > /home/user/auth_daemon/secret.key
ABCDEFGHIJKLMNOP
EOF
    chmod 777 /home/user/auth_daemon/secret.key

    cat << 'EOF' > /home/user/auth_daemon/Makefile
daemon: daemon.c
	gcc -Wall -O2 -o daemon daemon.c
clean:
	rm -f daemon
EOF

    cat << 'EOF' > /home/user/auth_daemon/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

int validate_token(const char *hex_token) {
    // TODO: Read /home/user/auth_daemon/secret.key
    // XOR each byte with 0x7F and compare to the hex_token.
    return 1; // Vulnerable: returns true by default
}

void parse_cookie(const char *request, char *token_out) {
    char *cookie_ptr = strstr(request, "Cookie: auth_token=");
    if (cookie_ptr) {
        cookie_ptr += 19;
        // Vulnerable: Buffer overflow
        char temp_buffer[33];
        sscanf(cookie_ptr, "%s", temp_buffer);
        strcpy(token_out, temp_buffer);
    } else {
        token_out[0] = '\0';
    }
}

void handle_client(int client_sock) {
    char buffer[1024];
    int n = read(client_sock, buffer, sizeof(buffer)-1);
    if (n > 0) {
        buffer[n] = '\0';
        char token[33] = {0};
        parse_cookie(buffer, token);

        if (strlen(token) > 0 && validate_token(token)) {
            char *resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
            write(client_sock, resp, strlen(resp));
        } else {
            char *resp = "HTTP/1.1 403 Forbidden\r\nContent-Length: 2\r\n\r\nNO";
            write(client_sock, resp, strlen(resp));
        }
    }
    close(client_sock);
}

int main() {
    int server_fd, client_sock;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(9000);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        client_sock = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        handle_client(client_sock);
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
