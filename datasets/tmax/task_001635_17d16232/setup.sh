#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/restore

    cat << 'EOF' > /home/user/restore/backup_service.py
import http.server
import socketserver

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"BACKUP_SERVICE_ONLINE")

httpd = socketserver.TCPServer(('127.0.0.1', 9090), Handler)
httpd.serve_forever()
EOF

    cat << 'EOF' > /home/user/restore/send_alert.sh
#!/bin/bash
echo "ALERT: Backup service is unreachable!" > /home/user/restore/alert.log
EOF
    chmod +x /home/user/restore/send_alert.sh

    cat << 'EOF' > /home/user/restore/health_monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>

#define TARGET_IP "192.0.2.100"
#define TARGET_PORT 9090

int check_service() {
    int sock;
    struct sockaddr_in server;

    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock == -1) return 0;

    server.sin_addr.s_addr = inet_addr(TARGET_IP);
    server.sin_family = AF_INET;
    server.sin_port = htons(TARGET_PORT);

    // Set timeout
    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 0;
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tv, sizeof tv);

    if (connect(sock, (struct sockaddr *)&server, sizeof(server)) < 0) {
        close(sock);
        return 0;
    }
    close(sock);
    return 1;
}

int main() {
    char *port_str = getenv("HEALTH_PORT");
    char *alert_script = getenv("ALERT_SCRIPT");

    if (!port_str || !alert_script) {
        fprintf(stderr, "Missing environment variables\n");
        return 1;
    }

    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    int port = atoi(port_str);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) exit(EXIT_FAILURE);
    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) exit(EXIT_FAILURE);

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(port);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) exit(EXIT_FAILURE);
    if (listen(server_fd, 3) < 0) exit(EXIT_FAILURE);

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) exit(EXIT_FAILURE);

        int status = check_service();
        char response[256];
        if (status) {
            sprintf(response, "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nSYSTEM_HEALTHY: Service reachable at %s:%d\n", TARGET_IP, TARGET_PORT);
        } else {
            system(alert_script);
            sprintf(response, "HTTP/1.1 503 Service Unavailable\nContent-Type: text/plain\n\nSYSTEM_ALERT: Service unreachable at %s:%d\n", TARGET_IP, TARGET_PORT);
        }

        write(new_socket, response, strlen(response));
        close(new_socket);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
