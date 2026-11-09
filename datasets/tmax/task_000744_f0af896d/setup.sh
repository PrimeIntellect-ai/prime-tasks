#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nginx redis-server
    pip3 install pytest flask websockets

    mkdir -p /app/src /app/bin /home/user/workspace

    # Create the Python reference script
    cat << 'EOF' > /app/src/sanitizer.py
import sys

def process(data):
    vowels = set("aeiouAEIOU")
    filtered = [c for c in data if c not in vowels]
    upper = "".join(filtered).upper()

    checksum = sum(ord(c) for c in upper) % 256
    return upper + f"{checksum:02X}"

if __name__ == "__main__":
    data = sys.stdin.read()
    sys.stdout.write(process(data))
EOF

    # Create the C++ oracle source and compile it
    cat << 'EOF' > /app/src/sanitizer_oracle.cpp
#include <iostream>
#include <string>

int main() {
    std::string data;
    char c;
    while (std::cin.get(c)) {
        data += c;
    }
    std::string vowels = "aeiouAEIOU";
    std::string upper;
    for (char ch : data) {
        if (vowels.find(ch) == std::string::npos) {
            upper += toupper((unsigned char)ch);
        }
    }
    int checksum = 0;
    for (char ch : upper) {
        checksum += (unsigned char)ch;
    }
    checksum %= 256;
    std::cout << upper;
    char buf[10];
    snprintf(buf, sizeof(buf), "%02X", checksum);
    std::cout << buf;
    return 0;
}
EOF

    g++ -O3 /app/src/sanitizer_oracle.cpp -o /app/bin/sanitizer_oracle
    rm /app/src/sanitizer_oracle.cpp

    # Create Nginx skeleton
    cat << 'EOF' > /home/user/workspace/nginx.conf
events {
    worker_connections 1024;
}

http {
    server {
        listen 8080;

        location /api/ {
            # TODO: Route to Flask backend on 127.0.0.1:5000
            # TODO: Preserve original Host header
        }

        location /stream/ {
            # TODO: Route to WebSocket backend on 127.0.0.1:5001
            # TODO: Preserve original Host header
            # TODO: Include Upgrade and Connection headers for WebSockets
        }
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
