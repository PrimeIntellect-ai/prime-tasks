#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc g++ valgrind
    pip3 install pytest

    mkdir -p /home/user/backend_feature
    cd /home/user/backend_feature

    cat << 'EOF' > libparser.h
#ifndef LIBPARSER_H
#define LIBPARSER_H

#ifdef __cplusplus
extern "C" {
#endif

char* parse_request(const char* input);

#ifdef __cplusplus
}
#endif

#endif
EOF

    cat << 'EOF' > libparser.c
#include "libparser.h"
#include <stdlib.h>
#include <string.h>

char* parse_request(const char* input) {
    char* result = malloc(strlen(input) + 1);
    strcpy(result, input);
    return result;
}
EOF

    cat << 'EOF' > processor.cpp
#include <iostream>
#include "libparser.h"

int main() {
#ifdef TARGET_WEB
    std::cout << "Mode: Web" << std::endl;
#elif defined(TARGET_NATIVE)
    std::cout << "Mode: Native" << std::endl;
#else
    std::cout << "Mode: Unknown" << std::endl;
#endif

    const char* req = "GET / HTTP/1.1";
    char* parsed = parse_request(req);
    std::cout << "Processed: " << parsed << std::endl;

    // Memory leak here: parsed is not freed.
    return 0;
}
EOF

    cat << 'EOF' > build.py
#!/usr/bin/env python3
import os
import subprocess
import sys

def run_cmd(cmd):
    print(f"Running: {cmd}")
    result = subprocess.run(cmd, shell=True)
    if result.returncode != 0:
        sys.exit(result.returncode)

def main():
    # TODO: Compile libparser.c to libparser.o using gcc

    # TODO: Compile processor.cpp and link with libparser.o to create 'processor_native' (define TARGET_NATIVE)

    # TODO: Compile processor.cpp and link with libparser.o to create 'processor_web' (define TARGET_WEB)
    pass

if __name__ == "__main__":
    main()
EOF

    chmod +x build.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
