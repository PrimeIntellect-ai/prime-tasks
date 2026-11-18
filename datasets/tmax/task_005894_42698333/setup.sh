#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > auth_handler.cpp
#include <iostream>
#include <string>

// SECRET_KEY_PLACEHOLDER

unsigned int generate_token(const std::string& url, const std::string& secret) {
    unsigned int hash = 5381;
    for (char c : url + secret) {
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    }
    return hash;
}

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    std::string url = argv[1];
    std::string provided_token = argv[2];

    std::string expected_token = std::to_string(generate_token(url, SECRET_KEY));

    if (provided_token == expected_token) {
        // Vulnerable redirect logic
        std::cout << "Location: " << url << "\n\n";
    } else {
        std::cout << "Status: 403 Forbidden\n\n";
    }
    return 0;
}
EOF

    cat auth_handler.cpp | sed 's/\/\/ SECRET_KEY_PLACEHOLDER/const std::string SECRET_KEY = "Inc1d3nt_R3sp0nse_K3y_8872!";/' > auth_handler_build.cpp
    g++ -O2 auth_handler_build.cpp -o auth_handler
    strip auth_handler
    rm auth_handler_build.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
