#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential curl
    pip3 install pytest

    mkdir -p /app

    cat << 'EOF' > /app/backend.py
import http.server
import socketserver
import json

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"status": "provisioned"}')

if __name__ == "__main__":
    with socketserver.TCPServer(("127.0.0.1", 9055), Handler) as httpd:
        httpd.serve_forever()
EOF

    cat << 'EOF' > /app/startup.sh
#!/bin/bash
python3 /app/backend.py &
EOF
    chmod +x /app/startup.sh

    cat << 'EOF' > /app/provision_events.log
[INFO] System starting up...
[DEBUG] Checking network interfaces...
[WARN] Deprecated config format detected.
[ROUTING_UPDATE] NEW_UPSTREAM_PORT=9055
[INFO] Backend provisioned successfully.
EOF

    cat << 'EOF' > /app/router.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

void handle_client(int client_sock, int target_port) {
    int target_sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in target_addr;
    target_addr.sin_family = AF_INET;
    target_addr.sin_port = htons(target_port);
    inet_pton(AF_INET, "127.0.0.1", &target_addr.sin_addr);

    if (connect(target_sock, (struct sockaddr *)&target_addr, sizeof(target_addr)) < 0) {
        close(client_sock);
        return;
    }

    fd_set read_fds;
    int max_fd = (client_sock > target_sock) ? client_sock : target_sock;
    char buffer[4096];

    while (1) {
        FD_ZERO(&read_fds);
        FD_SET(client_sock, &read_fds);
        FD_SET(target_sock, &read_fds);

        if (select(max_fd + 1, &read_fds, NULL, NULL, NULL) < 0) break;

        if (FD_ISSET(client_sock, &read_fds)) {
            ssize_t bytes = read(client_sock, buffer, sizeof(buffer));
            if (bytes <= 0) break;
            write(target_sock, buffer, bytes);
        }

        if (FD_ISSET(target_sock, &read_fds)) {
            ssize_t bytes = read(target_sock, buffer, sizeof(buffer));
            if (bytes <= 0) break;
            write(client_sock, buffer, bytes);
        }
    }

    close(client_sock);
    close(target_sock);
}

int main() {
    FILE *f = fopen("/home/user/upstream.conf", "r");
    if (!f) {
        fprintf(stderr, "Failed to open upstream.conf\n");
        return 1;
    }
    int target_port;
    fscanf(f, "%d", &target_port);
    fclose(f);

    int listen_port = 80;

    int server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in server_addr;
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(listen_port);

    if (bind(server_sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        fprintf(stderr, "Bind failed on port %d\n", listen_port);
        return 1;
    }
    listen(server_sock, 10);

    while (1) {
        int client_sock = accept(server_sock, NULL, NULL);
        if (client_sock >= 0) {
            if (fork() == 0) {
                close(server_sock);
                handle_client(client_sock, target_port);
                exit(0);
            }
            close(client_sock);
        }
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
