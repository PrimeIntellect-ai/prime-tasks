#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc curl
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/auth_service

    cat << 'EOF' > /home/user/auth_service/old_secret.key
alpha_legacy_992
EOF

    cat << 'EOF' > /home/user/auth_service/new_secret.key
omega_secure_114
EOF

    cat << 'EOF' > /home/user/auth_service/auth.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

// Simple Base64 decoder provided for the agent
static const int b64index[256] = {
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,
    0,0,0,0,0,0,0,0,0,0,0,62,63,62,62,63,52,53,54,55,56,57,58,59,60,61,0,0,0,0,0,0,
    0,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,0,0,0,0,63,
    0,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51
};
void b64_decode(const char *in, char *out) {
    int len = strlen(in);
    int i, j = 0;
    for (i = 0; i < len; i += 4) {
        int n = b64index[(int)in[i]] << 18 | b64index[(int)in[i+1]] << 12 | b64index[(int)in[i+2]] << 6 | b64index[(int)in[i+3]];
        out[j++] = n >> 16;
        if (in[i+2] != '=') out[j++] = n >> 8 & 0xFF;
        if (in[i+3] != '=') out[j++] = n & 0xFF;
    }
    out[j] = '\0';
}

void read_file(const char *path, char *buffer, size_t size) {
    FILE *f = fopen(path, "r");
    if (f) {
        fgets(buffer, size, f);
        buffer[strcspn(buffer, "\r\n")] = 0;
        fclose(f);
    }
}

int main() {
    int server_fd, new_socket;
    struct sockaddr_in address;
    int opt = 1;
    int addrlen = sizeof(address);
    char buffer[2048] = {0};

    char old_secret[256] = {0};
    read_file("/home/user/auth_service/old_secret.key", old_secret, sizeof(old_secret));

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    address.sin_family = AF_INET;
    address.sin_addr.s_addr = INADDR_ANY;
    address.sin_port = htons(8080);

    bind(server_fd, (struct sockaddr *)&address, sizeof(address));
    listen(server_fd, 3);

    while(1) {
        new_socket = accept(server_fd, (struct sockaddr *)&address, (socklen_t*)&addrlen);
        read(new_socket, buffer, 2048);

        char *auth_header = strstr(buffer, "Authorization: Bearer ");
        char *redirect_param = strstr(buffer, "redirect=");

        char redirect_url[256] = "/";
        if (redirect_param) {
            sscanf(redirect_param, "redirect=%255s", redirect_url);
            char *space = strchr(redirect_url, ' ');
            if (space) *space = '\0';
        }

        int authenticated = 0;
        if (auth_header) {
            char b64_token[256] = {0};
            sscanf(auth_header, "Authorization: Bearer %255s", b64_token);
            char *crlf = strstr(b64_token, "\r");
            if (crlf) *crlf = '\0';

            char decoded_token[256] = {0};
            b64_decode(b64_token, decoded_token);

            if (strcmp(decoded_token, old_secret) == 0) {
                authenticated = 1;
            }
        }

        char response[1024];
        if (authenticated) {
            sprintf(response, "HTTP/1.1 302 Found\r\nLocation: %s\r\n\r\n", redirect_url);
        } else {
            sprintf(response, "HTTP/1.1 401 Unauthorized\r\n\r\n");
        }

        write(new_socket, response, strlen(response));
        close(new_socket);
        memset(buffer, 0, sizeof(buffer));
    }
    return 0;
}
EOF

    chmod +x /home/user/auth_service/auth.c
    chmod -R 777 /home/user
