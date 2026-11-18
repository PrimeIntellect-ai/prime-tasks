#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr imagemagick fonts-dejavu cmake build-essential
    pip3 install pytest

    mkdir -p /app/pr_assets/
    convert -size 400x100 xc:white -font DejaVu-Sans -pointsize 24 -fill black -draw "text 20,50 'WAF-SEC-99821'" /app/pr_assets/token.png

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/miniwaf/src
    cat << 'EOF' > /home/user/miniwaf/CMakeLists.txt
cmake_minimum_required(VERSION 3.10)
project(MiniWAF)

set(CMAKE_C_STANDARD 99)

add_library(http_parser SHARED src/parser.c)
add_executable(miniwaf_server src/main.c)

# BUG: Missing target_link_libraries
EOF

    cat << 'EOF' > /home/user/miniwaf/src/parser.c
#include <string.h>
#include <stdio.h>

void parse_header(const char* input_header) {
    char buffer[128];
    // MEMORY BUG: unsafe strcpy
    strcpy(buffer, input_header);
    printf("Parsed header: %s\n", buffer);
}
EOF

    cat << 'EOF' > /home/user/miniwaf/src/main.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

extern void parse_header(const char* input_header);

int main(int argc, char **argv) {
    if (argc < 2) {
        printf("Missing token\n");
        return 1;
    }
    char* expected_token = argv[1];

    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);

    if ((server_fd = socket(AF_INET, SOCK_STREAM, 0)) == 0) {
        perror("socket failed");
        exit(EXIT_FAILURE);
    }

    if (setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR | SO_REUSEPORT, &opt, sizeof(opt))) {
        perror("setsockopt");
        exit(EXIT_FAILURE);
    }
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = inet_addr("127.0.0.1");
    address.sin_port = htons(8080);

    if (bind(server_fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        perror("bind failed");
        exit(EXIT_FAILURE);
    }
    if (listen(server_fd, 3) < 0) {
        perror("listen");
        exit(EXIT_FAILURE);
    }

    while(1) {
        if ((new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen)) < 0) {
            perror("accept");
            exit(EXIT_FAILURE);
        }
        char buffer[1024] = {0};
        read(new_socket, buffer, 1024);

        // Very rudimentary WAF and routing
        if (strstr(buffer, "<script>")) {
            char *resp = "HTTP/1.1 403 Forbidden\n\nBlocked by WAF";
            write(new_socket, resp, strlen(resp));
        } else {
            // Trigger parser bug if header is long
            char *header_start = strstr(buffer, "X-Custom-Header: ");
            if (header_start) {
                header_start += 17;
                char *header_end = strstr(header_start, "\r\n");
                if (header_end) {
                    char temp[1024] = {0};
                    strncpy(temp, header_start, header_end - header_start);
                    parse_header(temp); // this will crash if > 128 and bug not fixed
                }
            }
            char *resp = "HTTP/1.1 200 OK\n\nOK";
            write(new_socket, resp, strlen(resp));
        }
        close(new_socket);
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
