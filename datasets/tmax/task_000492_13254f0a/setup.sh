#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/app /home/user/logs

    # 1. Create the legacy binary containing the hardcoded key
    cat << 'EOF' > /home/user/app/old_auth.cpp
#include <iostream>
#include <string>

int main() {
    std::string api_key = "sk_live_9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c";
    std::cout << "Starting old auth service..." << std::endl;
    return 0;
}
EOF
    g++ /home/user/app/old_auth.cpp -o /home/user/app/old_auth.bin
    rm /home/user/app/old_auth.cpp

    # 2. Create the vulnerable new C++ code (CWE-79)
    cat << 'EOF' > /home/user/app/new_auth.cpp
#include <iostream>
#include <string>
#include <cstdlib>

void render_dashboard(const std::string& username) {
    // VULNERABILITY: Directly echoing unsanitized user input into HTML output (CWE-79)
    std::cout << "Content-Type: text/html\n\n";
    std::cout << "<html><body><h1>Welcome, " << username << "!</h1></body></html>";
}

int main(int argc, char** argv) {
    if (argc > 1) {
        render_dashboard(argv[1]);
    }
    return 0;
}
EOF

    # 3. Create the log file with the leaked key
    cat << 'EOF' > /home/user/logs/access.log
[2023-10-01 10:00:00] GET /api/data?key=sk_live_9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c HTTP/1.1
[2023-10-01 10:05:00] POST /api/update HTTP/1.1 - Success
[2023-10-01 10:10:00] GET /api/data?key=sk_live_9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c HTTP/1.1
[2023-10-01 10:15:00] GET /health HTTP/1.1
EOF

    chown -R user:user /home/user/app /home/user/logs
    chmod -R 777 /home/user
