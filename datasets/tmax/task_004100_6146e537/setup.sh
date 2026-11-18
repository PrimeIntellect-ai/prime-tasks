#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip python3-opencv g++ make curl
    pip3 install pytest

    # Create app directory
    mkdir -p /app

    # Generate the video artefact
    cat << 'EOF' > /tmp/generate_video.py
import cv2
import numpy as np

text = "--- parser.cpp\n+++ parser.cpp\n@@ -10,3 +10,3 @@\n-    int result = left - right;\n+    int result = left * right;\nAUTH_EXPR=12+4*5\n"

bits = []
for char in text:
    for bit in format(ord(char), '08b'):
        bits.append(int(bit))

out = cv2.VideoWriter('/app/deployment_signal.mp4', cv2.VideoWriter_fourcc(*'mp4v'), 1.0, (1920, 1080))
for bit in bits:
    color = 255 if bit == 1 else 0
    frame = np.full((1080, 1920, 3), color, dtype=np.uint8)
    out.write(frame)
out.release()
EOF
    python3 /tmp/generate_video.py
    rm /tmp/generate_video.py

    # Create user and codebase directory
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/evaluator

    # Write parser.h
    cat << 'EOF' > /home/user/evaluator/parser.h
#pragma once
#include <string>
int evaluate_expression(const std::string& expr);
EOF

    # Write parser.cpp
    cat << 'EOF' > /home/user/evaluator/parser.cpp
#include "parser.h"
#include <sstream>

int evaluate_expression(const std::string& expr) {
    // simplified mock parser for the test
    int left, right;
    char op;
    std::stringstream ss(expr);
    ss >> left >> op >> right;
    if (op == '+') return left + right;
    if (op == '*') {
    int result = left - right;
        return result;
    }
    return 0;
}
EOF

    # Write main.cpp
    cat << 'EOF' > /home/user/evaluator/main.cpp
#include <iostream>
#include <string>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <cstring>
#include "parser.h"

int main() {
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in address;
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(true) {
        int new_socket = accept(server_fd, nullptr, nullptr);
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        std::string request(buffer);
        // Agent must implement header parsing, auth checking, and routing
        // and call evaluate_expression(body)

        std::string response = "HTTP/1.1 401 Unauthorized\r\n\r\n";
        send(new_socket, response.c_str(), response.length(), 0);
        close(new_socket);
    }
    return 0;
}
EOF

    # Set permissions
    chmod -R 777 /home/user
    chmod -R 777 /app
