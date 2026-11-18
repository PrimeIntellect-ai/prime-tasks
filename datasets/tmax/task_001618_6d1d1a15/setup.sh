#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ make wget curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/project/src
    cd /home/user/project

    wget -qO src/httplib.h https://raw.githubusercontent.com/yhirose/cpp-httplib/master/httplib.h

    cat << 'EOF' > src/checksum.h
#ifndef CHECKSUM_H
#define CHECKSUM_H

int calculate_checksum(const char* data);

#endif
EOF

    cat << 'EOF' > src/checksum.cpp
#include "checksum.h"

int calculate_checksum(const char* data) {
    int sum = 0;
    for (int i = 0; data[i] != '\0'; i++) {
        sum += data[i];
    }
    return sum % 256;
}
EOF

    cat << 'EOF' > src/main.cpp
#include "httplib.h"
#include <iostream>
#include <vector>
#include <string>
#include <sstream>
#include <algorithm>
#include <dlfcn.h>

using namespace httplib;

std::vector<int> parse_list(const std::string& s) {
    std::vector<int> res;
    std::stringstream ss(s);
    std::string item;
    while (std::getline(ss, item, ',')) {
        res.push_back(std::stoi(item));
    }
    return res;
}

int main() {
    void* handle = dlopen("./libchecksum.so", RTLD_LAZY);
    if (!handle) {
        std::cerr << "Cannot open library: " << dlerror() << '\n';
        return 1;
    }

    typedef int (*checksum_func_t)(const char*);
    checksum_func_t calc = (checksum_func_t) dlsym(handle, "calculate_checksum");
    if (!calc) {
        std::cerr << "Cannot load symbol: " << dlerror() << '\n';
        return 1;
    }

    Server svr;

    svr.Get("/diff", [](const Request& req, Response& res) {
        if (req.has_param("list_a") && req.has_param("list_b")) {
            auto list_a = parse_list(req.get_param_value("list_a"));
            auto list_b = parse_list(req.get_param_value("list_b"));

            // BUG: Not sorting before set_difference, and set_difference needs sorted ranges.
            std::vector<int> diff;
            std::set_difference(list_a.begin(), list_a.end(),
                                list_b.begin(), list_b.end(),
                                std::back_inserter(diff));

            std::string out = "[";
            for(size_t i=0; i<diff.size(); ++i) {
                out += std::to_string(diff[i]);
                if (i != diff.size() - 1) out += ", ";
            }
            out += "]";
            res.set_content(out, "application/json");
        } else {
            res.status = 400;
        }
    });

    svr.listen("127.0.0.1", 8080);
    return 0;
}
EOF

    cat << 'EOF' > Makefile
all: safehashed libchecksum.so

# Broken: missing -fPIC, -shared for lib, missing -ldl for main
libchecksum.so: src/checksum.cpp
	g++ src/checksum.cpp -o libchecksum.so

safehashed: src/main.cpp
	g++ -std=c++17 src/main.cpp -o safehashed
EOF

    chown -R user:user /home/user/project
    chmod -R 777 /home/user
