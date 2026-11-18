#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip g++ binutils
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/fw_updater.cpp
#include <iostream>
#include <fstream>
#include <string>

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <manifest>\n";
        return 1;
    }

    std::ifstream file(argv[1]);
    std::string user, algo, rule, signature;

    std::getline(file, user);
    std::getline(file, algo);
    std::getline(file, rule);
    std::getline(file, signature);

    if (algo == "ALGO: NONE") {
        std::cout << "Warning: Signature verification bypassed.\n";
    } else {
        if (signature != "SIG: VALID") {
            std::cerr << "Invalid signature\n";
            return 1;
        }
    }

    std::cout << "Applied rule: " << rule << " for user " << user << "\n";
    return 0;
}
EOF

g++ -no-pie /home/user/fw_updater.cpp -o /home/user/fw_updater

cat << 'EOF' > /home/user/fw.log
[INFO] 2023-10-24 10:01:22 - User: alice - Algo: RSA256 - Rule: ALLOW PORT 80 - SigVerify: SUCCESS
[INFO] 2023-10-24 10:05:15 - User: bob - Algo: RSA256 - Rule: ALLOW PORT 443 - SigVerify: SUCCESS
[INFO] 2023-10-24 10:42:01 - User: mallory - Algo: NONE - Rule: ALLOW PORT 1337 - SigVerify: BYPASSED
[INFO] 2023-10-24 11:15:33 - User: charlie - Algo: RSA256 - Rule: ALLOW PORT 22 - SigVerify: SUCCESS
EOF

chmod -R 777 /home/user
