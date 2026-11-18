#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ openssl
pip3 install pytest

mkdir -p /home/user/src
mkdir -p /home/user/data

cat << 'EOF' > /home/user/src/data_proxy.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstring>
#include <unistd.h>

int main(int argc, char* argv[]) {
    if (argc < 3) {
        std::cerr << "Usage: " << argv[0] << " <input> <output>" << std::endl;
        return 1;
    }

    if (access("/home/user/certs/server.crt", F_OK) == -1 || access("/home/user/certs/server.key", F_OK) == -1) {
        std::cerr << "TLS Certificates missing." << std::endl;
        return 1;
    }

    std::ifstream policy("/home/user/rules.conf");
    std::string blocked_ip;
    if (policy.is_open()) {
        std::string line;
        while (getline(policy, line)) {
            if (line.find("BLOCK=") == 0) {
                blocked_ip = line.substr(6);
            }
        }
    } else {
        std::cerr << "Policy file missing." << std::endl;
        return 1;
    }

    std::ifstream traffic(argv[1]);
    std::ofstream out(argv[2]);
    std::string t_line;
    while (getline(traffic, t_line)) {
        size_t space = t_line.find(" ");
        if (space != std::string::npos) {
            std::string ip = t_line.substr(0, space);
            std::string data = t_line.substr(space + 1);

            if (ip == blocked_ip) continue;

            char buffer[64];
            // VULNERABILITY: CWE-120 Buffer Overflow
            strcpy(buffer, data.c_str());

            out << "ALLOWED: " << ip << " - " << buffer << std::endl;
        }
    }
    return 0;
}
EOF

cat << 'EOF' > /home/user/data/traffic.txt
192.168.1.1 NORMAL_PAYLOAD
10.99.0.42 MALICIOUS_PAYLOAD_DROP_ME
192.168.1.2 THIS_IS_A_VERY_LONG_STRING_THAT_WILL_DEFINITELY_CAUSE_A_BUFFER_OVERFLOW_IF_NOT_PROPERLY_HANDLED_BY_THE_CPP_APPLICATION_AAAAA
10.0.0.5 SHORT_DATA
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
