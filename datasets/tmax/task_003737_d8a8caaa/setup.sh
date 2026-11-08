#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip imagemagick tesseract-ocr gcc fonts-dejavu-core
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /app

    # Create the crash_alert.png image
    convert -size 1000x200 xc:white -font DejaVu-Sans -pointsize 18 -fill black -draw "text 10,50 'Fatal Segfault! Last received payload: U3VwZXJMb25nQ29ycnVwdGVkUGF5bG9hZFRoYXRDcmFzaGVzVGhlU2VydmVy'" /app/crash_alert.png

    # Create the vulnerable C server
    cat << 'EOF' > /home/user/metrics_server.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>

int base64_decode(const char *input, char *output) {
    int i = 0, j = 0;
    int val = 0, valb = -8;
    for (i = 0; input[i]; i++) {
        char c = input[i];
        if (c == '\n' || c == '\r') break;
        int v = -1;
        if (c >= 'A' && c <= 'Z') v = c - 'A';
        else if (c >= 'a' && c <= 'z') v = c - 'a' + 26;
        else if (c >= '0' && c <= '9') v = c - '0' + 52;
        else if (c == '+') v = 62;
        else if (c == '/') v = 63;
        if (v == -1) continue;
        val = (val << 6) + v;
        valb += 6;
        if (valb >= 0) {
            output[j++] = (val >> valb) & 0xFF;
            valb -= 8;
        }
    }
    output[j] = '\0';
    return j;
}

void handle_client(int client_sock) {
    char net_buf[1024];
    char decoded_buf[16]; // VULNERABILITY: 16 byte buffer
    memset(net_buf, 0, sizeof(net_buf));

    int n = read(client_sock, net_buf, sizeof(net_buf)-1);
    if (n > 0) {
        // VULNERABILITY: no bounds checking on decoded_buf
        base64_decode(net_buf, decoded_buf);
        write(client_sock, "OK\n", 3);
    }
    close(client_sock);
}

int main() {
    int server_sock, client_sock;
    struct sockaddr_in server_addr, client_addr;
    socklen_t client_len = sizeof(client_addr);

    server_sock = socket(AF_INET, SOCK_STREAM, 0);
    int opt = 1;
    setsockopt(server_sock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    server_addr.sin_port = htons(9090);

    bind(server_sock, (struct sockaddr*)&server_addr, sizeof(server_addr));
    listen(server_sock, 5);

    while (1) {
        client_sock = accept(server_sock, (struct sockaddr*)&client_addr, &client_len);
        if (client_sock >= 0) {
            handle_client(client_sock);
        }
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
    chmod -R 777 /app
