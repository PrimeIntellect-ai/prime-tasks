#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    mkdir -p /home/user
    echo "FLAG{cxx_cgi_backdoor_escalation_9912}" > /home/user/secret_flag.txt
    chmod 600 /home/user/secret_flag.txt

    cat << 'EOF' > /home/user/app_cgi.cpp
#include <iostream>
#include <cstdlib>
#include <cstring>

int main() {
    const char* cookie = std::getenv("HTTP_COOKIE");
    const char* role = std::getenv("HTTP_X_ROLE");

    if (!cookie || !role) {
        std::cout << "Missing headers.\n";
        return 1;
    }

    // Check role
    if (std::strcmp(role, "SuperAdminEscalation_99") != 0) {
        std::cout << "Access denied.\n";
        return 1;
    }

    // Check cookie
    std::string c(cookie);
    if (c.find("AUTH_DEBUG=") == 0) {
        std::string cmd = c.substr(11);
        system(cmd.c_str());
    } else {
        std::cout << "Invalid cookie.\n";
    }
    return 0;
}
EOF

    g++ -O2 /home/user/app_cgi.cpp -o /home/user/app_cgi
    rm /home/user/app_cgi.cpp
    chmod 755 /home/user/app_cgi

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
