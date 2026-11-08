#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ binutils
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > analyzer.cpp
#include <iostream>
#include <cstdlib>
#include <string>

int main(int argc, char* argv[]) {
    // Hidden debug variable inside binary: ANALYZE_DBG_X77
    const char* hidden_env = "ANALYZE_DBG_X77";

    if (argc == 4) {
        std::string a = argv[1];
        std::string b = argv[2];
        std::string c = argv[3];

        if (a == "DROP" && b == "TABLE" && c == "USERS") {
            if (std::getenv(hidden_env) != nullptr && std::string(std::getenv(hidden_env)) == "1") {
                std::cout << "VULNERABILITY_CONFIRMED: SQL_INJECTION_BYPASS" << std::endl;
                return 0;
            } else {
                // Silent segfault simulation
                return 139;
            }
        }
    }
    return 0;
}
EOF

    g++ -O2 analyzer.cpp -o analyzer
    rm analyzer.cpp

    cat << 'EOF' > service.log
[10:00:00] [PID 101] Service started
[10:00:01] [PID 102] Service started
[10:00:01] [PID 101] Processed input: SELECT
[10:00:02] [PID 102] Processed input: DROP
[10:00:02] [PID 101] Processed input: *
[10:00:03] [PID 102] Processed input: TABLE
[10:00:03] [PID 101] Processed input: FROM
[10:00:04] [PID 102] Processed input: USERS
[10:00:04] [PID 101] Processed input: ADMINS
[10:00:05] [PID 102] FATAL: SEGFAULT
[10:00:06] [PID 101] Shutdown graceful
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
