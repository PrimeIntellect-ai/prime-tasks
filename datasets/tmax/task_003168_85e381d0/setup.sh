#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ python3-opencv python3-numpy
pip3 install --default-timeout=100 pytest

mkdir -p /app

cat << 'EOF' > /app/oracle_filter.cpp
#include <iostream>
#include <string>

int main() {
    std::string input;
    char c;
    while (std::cin.get(c)) {
        input += c;
    }

    std::string token = "X9vPq2";
    std::string csp = "default-src 'self'";
    std::string block = "alert(1)";

    size_t first_nl = input.find('\n');
    if (first_nl == std::string::npos) {
        if (input != "AUTH " + token) {
            std::cout << "401\n";
            return 1;
        }
        std::cout << "400\n";
        return 1;
    }

    std::string line1 = input.substr(0, first_nl);
    if (line1 != "AUTH " + token) {
        std::cout << "401\n";
        return 1;
    }

    if (input.length() <= first_nl + 1 || input[first_nl + 1] != '\n') {
        std::cout << "400\n";
        return 1;
    }

    std::string body = input.substr(first_nl + 2);
    if (body.find(block) != std::string::npos) {
        std::cout << "403\n";
        return 1;
    }

    std::cout << "200\nCSP: " << csp << "\n" << body;
    return 0;
}
EOF

g++ -O3 -o /app/oracle_filter /app/oracle_filter.cpp

cat << 'EOF' > /app/generate_video.py
import cv2
import numpy as np

text = "CREDENTIAL|X9vPq2|CSP|default-src 'self'|BLOCK|alert(1)"
binary = ''.join(format(ord(c), '08b') for c in text)

width, height = 320, 240
fps = 10

out = cv2.VideoWriter('/app/rotation_data.mp4', cv2.VideoWriter_fourcc(*'mp4v'), fps, (width, height))

for bit in binary:
    frame = np.zeros((height, width, 3), dtype=np.uint8)
    if bit == '1':
        frame[:] = (0, 0, 255) # BGR for Red
    else:
        frame[:] = (0, 255, 0) # BGR for Green
    out.write(frame)

out.release()
EOF

python3 /app/generate_video.py

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
