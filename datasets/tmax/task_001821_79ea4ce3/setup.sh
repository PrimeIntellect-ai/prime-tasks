#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ imagemagick fonts-dejavu
    pip3 install pytest

    mkdir -p /app
    mkdir -p /home/user

    # Generate the image with the Master PIN
    convert -size 800x200 xc:white -font DejaVu-Sans -pointsize 24 -fill black -annotate +50+100 "System uptime: 45 days. MASTER_PIN: 7392. Port: 8080." /app/admin_dashboard.png

    # Create the oracle implementation
    cat << 'EOF' > /app/oracle.cpp
#include <iostream>
#include <string>
#include <regex>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cout << "INVALID\n";
        return 0;
    }
    std::string token = argv[1];
    std::regex re("^([0-9]+)-([0-9]+)-([0-9]+)$");
    std::smatch match;
    if (std::regex_match(token, match, re)) {
        try {
            unsigned long long userid = std::stoull(match[1].str());
            unsigned long long timestamp = std::stoull(match[2].str());
            unsigned long long signature = std::stoull(match[3].str());
            if (userid > 0 && timestamp > 0 && signature == (userid * 3) + timestamp + 7392) {
                std::cout << "VALID\n";
                return 0;
            }
        } catch (...) {
            // Catch out of range exceptions
        }
    }
    std::cout << "INVALID\n";
    return 0;
}
EOF

    g++ -O3 /app/oracle.cpp -o /app/oracle_check_auth
    chmod +x /app/oracle_check_auth
    rm /app/oracle.cpp

    # Create the flawed legacy implementation
    cat << 'EOF' > /home/user/legacy_auth.cpp
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char* argv[]) {
    if (argc != 2) return 1;
    char userid[10];
    char timestamp[10];
    char signature[10];

    // Vulnerable to buffer overflow
    sscanf(argv[1], "%[^-]-%[^-]-%s", userid, timestamp, signature);

    int u = atoi(userid);
    int t = atoi(timestamp);
    int s = atoi(signature);

    if (u > 0 && t > 0 && s == (u * 3) + t + 7392) {
        printf("VALID\n");
    } else {
        printf("INVALID\n");
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 755 /app
