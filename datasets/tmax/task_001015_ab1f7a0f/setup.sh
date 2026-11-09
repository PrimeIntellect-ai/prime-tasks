#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user

    cat << 'EOF' > /home/user/audit_logs.txt
[2023-10-01 10:00:01] GET /redirect?url=google.com&session=abc123xyz
[2023-10-01 10:05:22] GET /login?user=admin
[2023-10-01 10:12:45] GET /redirect?url=malicious-redirect.local&session=SEC-998877-TOK
[2023-10-01 10:15:30] GET /redirect?url=yahoo.com&session=def456uvw
EOF

    cat << 'EOF' > /home/user/auth_service.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

void handle_client(int client_sock) {
    char buffer[1024];
    int bytes_read = read(client_sock, buffer, sizeof(buffer) - 1);
    if (bytes_read > 0) {
        buffer[bytes_read] = '\0';

        char url[256] = {0};
        char session[256] = {0};

        // Very basic extraction for GET /redirect?url=...&session=...
        char *url_ptr = strstr(buffer, "url=");
        char *session_ptr = strstr(buffer, "session=");

        if (url_ptr && session_ptr) {
            sscanf(url_ptr, "url=%255[^& \r\n]", url);
            sscanf(session_ptr, "session=%255[^& \r\n]", session);

            // Vulnerability: command injection via system()
            char cmd[1024];
            snprintf(cmd, sizeof(cmd), "echo 'User redirected to %s with session %s' > /dev/null", url, session);
            system(cmd);

            char *response = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
            write(client_sock, response, strlen(response));
        }
    }
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(8080);

    bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr));
    listen(server_sock, 5);

    while(1) {
        client_sock = accept(server_sock, (struct sockaddr *)&client_addr, &client_len);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
