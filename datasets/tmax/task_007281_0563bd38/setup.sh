#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ gdb binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/log_processor.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstdlib>

void parse_log_entry(const std::string& line) {
    size_t pos = line.find("code:");
    if (pos != std::string::npos) {
        int code = std::stoi(line.substr(pos + 5));
        if (code > 0) {
            // Algorithmic bug: division by zero if code is a multiple of 1337
            int divisor = code % 1337;
            int metric = 10000 / divisor; 
            if (metric > 0) {
                // do nothing, just prevent optimization
            }
        }
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <logfile>\n";
        return 1;
    }
    std::ifstream file(argv[1]);
    std::string line;
    while (std::getline(file, line)) {
        parse_log_entry(line);
    }
    return 0;
}
EOF

    g++ -g -O0 /tmp/log_processor.cpp -o /home/user/log_processor
    rm /tmp/log_processor.cpp

    cat << 'EOF' > /tmp/gen_logs.py
import random
with open('/home/user/app_logs.txt', 'w') as f:
    for i in range(5000):
        code = random.randint(1, 1300)
        f.write(f"[INFO] Request processed successfully with code:{code}\n")
    # The crashing line
    f.write("[DEBUG] Background job failed, retrying with code:2674\n")
    for i in range(100):
        code = random.randint(1, 1300)
        f.write(f"[INFO] Request processed successfully with code:{code}\n")
EOF
    python3 /tmp/gen_logs.py
    rm /tmp/gen_logs.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
