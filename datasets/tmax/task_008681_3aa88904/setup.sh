#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ openssl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/deploy

    cat << 'EOF' > /home/user/rotate_cli.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc != 4) {
        std::cerr << "Usage: " << argv[0] << " <cert_path> <key_path> <status_msg>\n";
        return 1;
    }

    std::string cert_path = argv[1];
    std::string key_path = argv[2];
    std::string status_msg = argv[3];

    // Deploy certificates
    std::string cmd1 = "cp " + cert_path + " /home/user/deploy/cert.pem";
    std::string cmd2 = "cp " + key_path + " /home/user/deploy/key.pem";

    system(cmd1.c_str());
    system(cmd2.c_str());

    // Generate HTML report
    std::ofstream report("/home/user/deploy/status.html");
    report << "<html><body><h1>Rotation Status</h1><p>" << status_msg << "</p></body></html>";
    report.close();

    std::cout << "Rotation complete.\n";
    return 0;
}
EOF

    chmod -R 777 /home/user
