#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

apt-get update && apt-get install -y python3 python3-pip nginx g++ openssl
pip3 install pytest

mkdir -p /app/backend /app/nginx /app/proxy

cat << 'EOF' > /app/backend/server.py
import http.server
import socketserver

class EchoHeaderHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"Backend received headers:\n")
        for key, value in self.headers.items():
            self.wfile.write(f"{key}: {value}\n".encode())
    def do_POST(self):
        self.do_GET()

with socketserver.TCPServer(("127.0.0.1", 8081), EchoHeaderHandler) as httpd:
    httpd.serve_forever()
EOF

cat << 'EOF' > /app/nginx/nginx.conf
events {
    worker_connections 1024;
}
http {
    server {
        # TODO: Configure listening on 8443 ssl
        # TODO: Configure ssl_certificate and ssl_certificate_key

        location / {
            # TODO: proxy_pass to http://127.0.0.1:8080
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

cat << 'EOF' > /app/proxy/proxy.cpp
#include <iostream>
#include <string>
#include <regex>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

std::string inspect_and_modify_http(const std::string& request, bool& drop_request) {
    std::string modified_request = request;
    drop_request = false;

    // TODO: Set drop_request = true if "UNION SELECT" or "<script>" is found
    // TODO: Redact the value of the session_id cookie to "REDACTED"

    return modified_request;
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
    if (listen(server_fd, 10) < 0) return 1;

    while(true) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) continue;

        char buffer[4096] = {0};
        read(new_socket, buffer, 4096);
        std::string req(buffer);

        bool drop = false;
        std::string mod_req = inspect_and_modify_http(req, drop);

        if (drop) {
            std::string forbidden = "HTTP/1.1 403 Forbidden\r\nContent-Length: 17\r\n\r\nMalicious payload";
            write(new_socket, forbidden.c_str(), forbidden.length());
        } else {
            int backend_sock = socket(AF_INET, SOCK_STREAM, 0);
            struct sockaddr_in serv_addr;
            serv_addr.sin_family = AF_INET;
            serv_addr.sin_port = htons(8081);
            inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);

            if (connect(backend_sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) >= 0) {
                write(backend_sock, mod_req.c_str(), mod_req.length());
                char back_buf[4096] = {0};
                int bytes = read(backend_sock, back_buf, 4096);
                write(new_socket, back_buf, bytes);
            }
            close(backend_sock);
        }
        close(new_socket);
    }
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
