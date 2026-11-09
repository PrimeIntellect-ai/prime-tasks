#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/app

    # Create backend.py
    cat << 'EOF' > /home/user/app/backend.py
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok", "path": self.path}).encode())

if __name__ == '__main__':
    server = HTTPServer(('127.0.0.1', 8081), RequestHandler)
    server.serve_forever()
EOF

    # Create gateway.c and compile it
    cat << 'EOF' > /home/user/app/gateway.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <dlfcn.h>

#define PORT 8080
#define BACKEND_PORT 8081

void handle_client(int client_socket, const char* client_ip) {
    char buffer[4096];
    int bytes_read = read(client_socket, buffer, sizeof(buffer) - 1);
    if (bytes_read <= 0) {
        close(client_socket);
        return;
    }
    buffer[bytes_read] = '\0';

    char method[16] = {0}, path[256] = {0};
    sscanf(buffer, "%15s %255s", method, path);

    void* handle = dlopen("./libgateway_plugins.so", RTLD_LAZY);
    int status = 500;
    if (handle) {
        int (*process_request)(const char*, const char*) = dlsym(handle, "process_request");
        if (process_request) {
            status = process_request(client_ip, path);
        }
        dlclose(handle);
    }

    char response[4096];
    if (status == 200) {
        int backend_sock = socket(AF_INET, SOCK_STREAM, 0);
        struct sockaddr_in backend_addr;
        backend_addr.sin_family = AF_INET;
        backend_addr.sin_port = htons(BACKEND_PORT);
        inet_pton(AF_INET, "127.0.0.1", &backend_addr.sin_addr);

        if (connect(backend_sock, (struct sockaddr*)&backend_addr, sizeof(backend_addr)) == 0) {
            char req[1024];
            snprintf(req, sizeof(req), "%s %s HTTP/1.0\r\n\r\n", method, path);
            send(backend_sock, req, strlen(req), 0);
            int bytes = read(backend_sock, response, sizeof(response) - 1);
            if (bytes > 0) {
                response[bytes] = '\0';
                write(client_socket, response, bytes);
            }
        } else {
            snprintf(response, sizeof(response), "HTTP/1.1 502 Bad Gateway\r\nContent-Length: 11\r\n\r\nBad Gateway");
            write(client_socket, response, strlen(response));
        }
        close(backend_sock);
    } else if (status == 403) {
        snprintf(response, sizeof(response), "HTTP/1.1 403 Forbidden\r\nContent-Length: 9\r\n\r\nForbidden");
        write(client_socket, response, strlen(response));
    } else if (status == 429) {
        snprintf(response, sizeof(response), "HTTP/1.1 429 Too Many Requests\r\nContent-Length: 17\r\n\r\nToo Many Requests");
        write(client_socket, response, strlen(response));
    } else {
        snprintf(response, sizeof(response), "HTTP/1.1 500 Internal Server Error\r\nContent-Length: 21\r\n\r\nInternal Server Error");
        write(client_socket, response, strlen(response));
    }
    close(client_socket);
}

int main() {
    int server_fd;
    struct sockaddr_in address;
    int opt = 1;

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(PORT);

    bind(server_fd, (struct sockaddr*)&address, sizeof(address));
    listen(server_fd, 10);

    while (1) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_socket = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_socket >= 0) {
            char client_ip[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &client_addr.sin_addr, client_ip, INET_ADDRSTRLEN);
            handle_client(client_socket, client_ip);
        }
    }
    return 0;
}
EOF

    cd /home/user/app
    gcc -o gateway_bin gateway.c -ldl
    rm gateway.c

    chown -R user:user /home/user
    chmod -R 777 /home/user
