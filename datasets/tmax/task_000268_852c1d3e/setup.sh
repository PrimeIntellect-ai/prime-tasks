#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make git
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/worker.cpp
#include <iostream>
#include <string>
#include <chrono>
#include <thread>
#include <fstream>
#include <cstdlib>

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <git_repo_path>\n";
        return 1;
    }
    std::string repo_path = argv[1];
    std::this_thread::sleep_for(std::chrono::milliseconds(1500));

    std::string cmd = "git -C " + repo_path + " rev-parse HEAD 2>/dev/null";
    char buffer[128];
    std::string result = "";
    FILE* pipe = popen(cmd.c_str(), "r");
    if (pipe) {
        while (fgets(buffer, sizeof(buffer), pipe) != NULL) {
            result += buffer;
        }
        pclose(pipe);
    }

    if (!result.empty() && result.back() == '\n') result.pop_back();
    if (result.empty()) result = "unknown";

    std::cout << "{\"commit\": \"" << result << "\", \"config\": \"generated_config_data\"}\n";
    return 0;
}
EOF

    g++ -O2 /tmp/worker.cpp -o /app/provision_worker
    strip /app/provision_worker
    chmod +x /app/provision_worker
    rm /tmp/worker.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
