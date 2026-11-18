#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/auth_service.cpp
#include <iostream>
#include <cstring>

void parse_http_header(const char* raw_request) {
    char header_buffer[128];
    // Vulnerability: strcpy without bounds checking
    strcpy(header_buffer, raw_request);
    std::cout << "Header parsed." << std::endl;
}

int main() {
    return 0;
}
EOF

    cat << 'EOF' > /home/user/sbox.txt
14 4 13 1 2 15 11 8 3 10 6 12 5 9 0 7
EOF

    cat << 'EOF' > /home/user/requests.log
POST /login HTTP/1.1
Host: example.com
User-Agent: Mozilla/5.0
CreditCard: 4111222233334444
Session-ID: 987654321

GET /checkout HTTP/1.1
Host: example.com
CC: 5555666677778888, Expiry: 12/25
Total: $12.50
EOF

    chmod -R 777 /home/user
