#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/src/v1
    mkdir -p /home/user/src/v2

    cat << 'EOF' > /home/user/src/v1/libdata.c
#include <string.h>

const char* get_version() {
    return "1.8.4";
}

void encode_data(const char* input, char* output) {
    int i = 0;
    while(input[i]) {
        output[i] = input[i] + 1; // Simple shift
        i++;
    }
    output[i] = '\0';
}
EOF

    cat << 'EOF' > /home/user/src/v2/libdata.c
#include <wchar.h>

const char* get_version() {
    return "2.1.0";
}

void encode_data_wide(const wchar_t* input, wchar_t* output) {
    int i = 0;
    while(input[i]) {
        output[i] = input[i] + 2; // Different shift for v2
        i++;
    }
    output[i] = L'\0';
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
