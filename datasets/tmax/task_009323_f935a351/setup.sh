#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client openssl g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/server_uploads
    mkdir -p /home/user/.ssh

    # Generate a dummy SSH key and encrypt it
    ssh-keygen -t rsa -b 2048 -f /home/user/dummy_key -N "" -q
    openssl enc -aes-256-cbc -salt -pbkdf2 -in /home/user/dummy_key.pub -out /home/user/new_key.pub.enc -pass pass:SecureRotate2024!
    rm -f /home/user/dummy_key

    # Create the skeleton C++ client
    cat << 'EOF' > /home/user/upload_client.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cstring>

int main() {
    // Read the public key
    std::ifstream keyFile("/home/user/new_key.pub");
    if (!keyFile) {
        std::cerr << "Failed to open key file\n";
        return 1;
    }
    std::stringstream buffer;
    buffer << keyFile.rdbuf();
    std::string body = buffer.str();

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serv_addr;
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_port = htons(9090);
    inet_pton(AF_INET, "127.0.0.1", &serv_addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&serv_addr, sizeof(serv_addr)) < 0) {
        std::cerr << "Connection Failed\n";
        return 1;
    }

    // VULNERABLE REQUEST - FIX THIS
    std::string request = "POST /upload?file=../../../home/user/.ssh/authorized_keys HTTP/1.1\r\n"
                          "Host: 127.0.0.1:9090\r\n"
                          "Content-Length: " + std::to_string(body.length()) + "\r\n"
                          "\r\n" + body;

    send(sock, request.c_str(), request.length(), 0);

    char resp_buffer[1024] = {0};
    read(sock, resp_buffer, 1024);
    std::cout << resp_buffer << std::endl;

    close(sock);
    return 0;
}
EOF

    # Create the Python validation server
    cat << 'EOF' > /home/user/server.py
import http.server
import socketserver
import urllib.parse
import os

class SecureHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        cookie = self.headers.get('Cookie', '')
        if 'auth=admin_rotate' not in cookie:
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b"Unauthorized")
            return

        parsed_path = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(parsed_path.query)
        filename = query.get('file', [''])[0]

        if not filename or '/' in filename or '..' in filename:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid filename or path traversal detected")
            return

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        # Save to secure uploads directory
        safe_path = os.path.join('/home/user/server_uploads', filename)
        with open(safe_path, 'wb') as f:
            f.write(body)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"Key rotated securely")

Handler = SecureHandler
httpd = socketserver.TCPServer(("127.0.0.1", 9090), Handler)
httpd.serve_forever()
EOF

    chmod -R 777 /home/user
