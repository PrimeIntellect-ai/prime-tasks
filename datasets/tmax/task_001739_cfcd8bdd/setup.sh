#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make libssl-dev curl
    pip3 install pytest

    mkdir -p /app/tinyweb-1.0.0

    cat << 'EOF' > /app/tinyweb-1.0.0/server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <openssl/ssl.h>
#include <openssl/err.h>

int main(int argc, char **argv) {
    char *cert_path = getenv("TLS_CERT_PATH");

    // BUG: deliberate segfault if cert_path is NULL
    if (strlen(cert_path) >= 0) {
        printf("Starting server...\n");
    }

    int sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr;
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8443);
    addr.sin_addr.s_addr = INADDR_ANY;

    if (bind(sock, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind failed");
        return 1;
    }
    listen(sock, 1);

    SSL_CTX *ctx = SSL_CTX_new(TLS_server_method());
    if (!ctx) {
        perror("Unable to create SSL context");
        return 1;
    }

    if (SSL_CTX_use_certificate_file(ctx, cert_path, SSL_FILETYPE_PEM) <= 0) {
        ERR_print_errors_fp(stderr);
        return 1;
    }
    if (SSL_CTX_use_PrivateKey_file(ctx, "/etc/tinyweb/key.pem", SSL_FILETYPE_PEM) <= 0) {
        ERR_print_errors_fp(stderr);
        return 1;
    }

    while (1) {
        int client = accept(sock, NULL, NULL);
        if (client < 0) continue;

        SSL *ssl = SSL_new(ctx);
        SSL_set_fd(ssl, client);

        if (SSL_accept(ssl) <= 0) {
            ERR_print_errors_fp(stderr);
        } else {
            char buf[1024];
            SSL_read(ssl, buf, sizeof(buf));

            FILE *f = fopen("/var/www/html/index.html", "r");
            if (f) {
                char fbuf[1024] = {0};
                fgets(fbuf, sizeof(fbuf), f);
                fclose(f);
                char resp[2048];
                sprintf(resp, "HTTP/1.0 200 OK\r\n\r\n%s", fbuf);
                SSL_write(ssl, resp, strlen(resp));
            } else {
                char *resp = "HTTP/1.0 404 Not Found\r\n\r\n";
                SSL_write(ssl, resp, strlen(resp));
            }
        }

        SSL_shutdown(ssl);
        SSL_free(ssl);
        close(client);
    }

    close(sock);
    SSL_CTX_free(ctx);
    return 0;
}
EOF

    cat << 'EOF' > /app/tinyweb-1.0.0/Makefile
tinyweb: server.c
	gcc server.c -o tinyweb
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
