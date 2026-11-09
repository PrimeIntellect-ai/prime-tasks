#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ nlohmann-json3-dev golang
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/proxy.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

int main(int argc, char* argv[]) {
    if (argc < 2) return 1;
    std::ifstream ifs(argv[1]);
    if (!ifs.is_open()) return 1;
    json j;
    try { ifs >> j; } catch (...) { return 1; }

    if (!j.contains("packages") || !j["packages"].is_array()) {
        std::cout << "{\"status\":\"allowed\",\"allowed_packages\":[]}\n";
        return 0;
    }

    auto packages = j["packages"];
    if (packages.size() > 5) {
        std::cout << "{\"status\":\"rate_limited\",\"allowed_packages\":[]}\n";
        return 0;
    }

    for (auto& pkg : packages) {
        std::string name = pkg.value("name", "");
        if (name.find("eval") != std::string::npos || name.find("exec") != std::string::npos) {
            std::cout << "{\"status\":\"blocked\",\"allowed_packages\":[]}\n";
            return 0;
        }
    }

    json allowed = json::array();
    for (auto& pkg : packages) {
        std::string eco = pkg.value("ecosystem", "");
        std::string ver = pkg.value("version", "");
        if (eco == "npm" && ver.find("0.") == 0) {
            continue;
        }
        allowed.push_back(pkg);
    }

    std::cout << "{\"status\":\"allowed\",\"allowed_packages\":" << allowed.dump() << "}\n";
    return 0;
}
EOF

    g++ -O3 -std=c++11 /tmp/proxy.cpp -o /app/build_sec_proxy
    strip /app/build_sec_proxy
    rm /tmp/proxy.cpp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
