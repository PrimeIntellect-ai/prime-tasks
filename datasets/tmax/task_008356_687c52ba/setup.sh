#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential cmake
    pip3 install pytest

    mkdir -p /home/user/project/src
    mkdir -p /home/user/project/tests

    cat << 'EOF' > /home/user/project/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(ProtoRest Bridge C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")

# Build shared library
add_library(protorest SHARED src/encoder.c)
target_include_directories(protorest PUBLIC src)

# Build test executable
add_executable(test_encoder tests/test_encoder.c)
target_include_directories(test_encoder PRIVATE src)
EOF

    cat << 'EOF' > /home/user/project/src/encoder.h
#ifndef ENCODER_H
#define ENCODER_H

#include <stddef.h>

void base64_encode(const unsigned char *data, size_t input_length, char *encoded_data);
void generate_rest_payload(const unsigned char *protobuf_data, size_t len, char *json_out);

#endif
EOF

    cat << 'EOF' > /home/user/project/src/encoder.c
#include "encoder.h"
#include <stdio.h>
#include <string.h>

static const char encoding_table[] = {'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',
                                      'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
                                      'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X',
                                      'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
                                      'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n',
                                      'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
                                      'w', 'x', 'y', 'z', '0', '1', '2', '3',
                                      '4', '5', '6', '7', '8', '9', '+', '/'};

void base64_encode(const unsigned char *data, size_t input_length, char *encoded_data) {
    size_t i = 0, j = 0;
    while (i < input_length) {
        unsigned char b1 = data[i++];
        unsigned char b2 = (i < input_length) ? data[i++] : 0;
        unsigned char b3 = (i < input_length) ? data[i++] : 0;

        encoded_data[j++] = encoding_table[b1 >> 2];
        encoded_data[j++] = encoding_table[((b1 & 0x03) << 4) | (b2 >> 4)];
        encoded_data[j++] = encoding_table[((b2 & 0x0f) << 2) | (b3 >> 6)];
        encoded_data[j++] = encoding_table[b3 & 0x3f];
    }
    encoded_data[j] = '\0';

    // BUG: Missing padding logic.
    // Correct logic would be:
    // int mod_table[] = {0, 2, 1};
    // for (int p = 0; p < mod_table[input_length % 3]; p++)
    //     encoded_data[j - 1 - p] = '=';
}

void generate_rest_payload(const unsigned char *protobuf_data, size_t len, char *json_out) {
    char b64_buffer[256] = {0};
    base64_encode(protobuf_data, len, b64_buffer);
    sprintf(json_out, "{\"payload\": \"%s\"}", b64_buffer);
}
EOF

    cat << 'EOF' > /home/user/project/tests/test_encoder.c
#include "encoder.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>

void test_basic_encode() {
    char json_out[256];
    generate_rest_payload((const unsigned char *)"A", 1, json_out);
    // Note: without padding, this evaluates to 'QQA' instead of 'QQ=='
    // But we just stubbed this basic test
}

int main() {
    test_basic_encode();
    printf("All tests passed.\n");
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
