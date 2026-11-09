#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ valgrind espeak
    pip3 install pytest

    mkdir -p /home/user/src
    mkdir -p /app

    # Create oracle source code
    cat << 'EOF' > /app/oracle_router.cpp
#include <iostream>
#include <string>
#include <vector>
#include <sstream>

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    std::string url = argv[1];
    std::string path;
    std::string params_str;
    size_t q_pos = url.find('?');
    if (q_pos != std::string::npos) {
        path = url.substr(0, q_pos);
        params_str = url.substr(q_pos + 1);
    } else {
        path = url;
    }

    int hash = 0;
    for (char c : path) {
        hash += static_cast<int>(c);
    }
    hash = hash % 251;

    std::cout << "Path: " << path << "\n";
    std::cout << "Hash: " << hash << "\n";

    if (params_str.empty()) {
        std::cout << "Params: none\n";
    } else {
        std::cout << "Params: ";
        std::stringstream ss(params_str);
        std::string token;
        while (std::getline(ss, token, '&')) {
            std::cout << token << ";";
        }
        std::cout << "\n";
    }
    return 0;
}
EOF

    # Compile oracle
    g++ -O3 /app/oracle_router.cpp -o /app/oracle_router
    rm /app/oracle_router.cpp

    # Generate audio
    espeak -w /app/artifact_routes.wav "The routing hash function must compute the sum of the ASCII values of all characters in the parsed URL path, and then return the result modulo two hundred fifty one."

    # Create buggy source code
    cat << 'EOF' > /home/user/src/router.cpp
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct Param {
    char key[50];
    char val[50];
    struct Param* next;
};

int main(int argc, char** argv) {
    if (argc != 2) return 1;
    char path[50];
    char* url = argv[1];
    char* q = strchr(url, '?');
    if (q) {
        strncpy(path, url, q - url);
        path[q - url] = '\0';
    } else {
        strcpy(path, url);
    }
    printf("Path: %s\n", path);
    printf("Hash: 0\n");
    if (!q || strlen(q) <= 1) {
        printf("Params: none\n");
        return 0;
    }
    printf("Params: ");
    char* p = q + 1;
    while (p && *p) {
        char* eq = strchr(p, '=');
        char* amp = strchr(p, '&');
        if (eq) {
            char k[50], v[50];
            strncpy(k, p, eq - p); k[eq - p] = '\0';
            if (amp) {
                strncpy(v, eq + 1, amp - eq - 1); v[amp - eq - 1] = '\0';
                p = amp + 1;
            } else {
                strcpy(v, eq + 1);
                p = NULL;
            }
            printf("%s=%s;", k, v);
        } else {
            break;
        }
    }
    printf("\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
