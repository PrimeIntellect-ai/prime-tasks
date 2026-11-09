#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest hypothesis

    mkdir -p /home/user/url_parser

    cat << 'EOF' > /home/user/url_parser/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(xss_check C)
add_library(xss_check SHARED xss_check.c)
EOF

    cat << 'EOF' > /home/user/url_parser/xss_check.c
#include <string.h>

struct Payload {
    char* content;
    int length;
    int has_xss;
};

void check_xss(struct Payload* p) {
    if (!p || !p->content) return;
    // Dummy check for testing
    if (strstr(p->content, "<script>") != NULL) {
        p->has_xss = 1;
    } else {
        p->has_xss = 0;
    }
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
