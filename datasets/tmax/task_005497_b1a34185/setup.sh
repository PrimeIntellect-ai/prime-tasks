#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /tmp/uploads
    chmod 777 /tmp/uploads

    cat << 'EOF' > /home/user/vulnerable_cgi.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char buffer[1024];
    int auth = 0;
    char filename[256] = "default_upload.bin";
    char body[1024] = {0};

    // Parse HTTP headers from stdin
    while(fgets(buffer, sizeof(buffer), stdin)) {
        if (strcmp(buffer, "\r\n") == 0 || strcmp(buffer, "\n") == 0) {
            break; // End of headers
        }
        // Check for hardcoded auth cookie
        if (strstr(buffer, "Cookie: admin_session=0xDEADBEEF_SECRET")) {
            auth = 1;
        }
        // Check for custom filename header
        if (strstr(buffer, "X-File-Target: ")) {
            sscanf(buffer, "X-File-Target: %255s", filename);
        }
    }

    if (!auth) {
        printf("HTTP/1.1 403 Forbidden\r\n\r\nAuthentication Failed.\n");
        return 1;
    }

    // Read HTTP body
    size_t bytes_read = fread(body, 1, sizeof(body)-1, stdin);
    body[bytes_read] = '\0';

    char out_path[512];
    snprintf(out_path, sizeof(out_path), "/tmp/uploads/%s", filename);

    FILE *f = fopen(out_path, "w");
    if(f) {
        fputs(body, f);
        fclose(f);
        printf("HTTP/1.1 200 OK\r\n\r\nFile uploaded successfully.\n");
    } else {
        printf("HTTP/1.1 500 Internal Server Error\r\n\r\nFailed to write file.\n");
    }
    return 0;
}
EOF

    gcc /home/user/vulnerable_cgi.c -o /home/user/vulnerable_cgi
    rm /home/user/vulnerable_cgi.c
    chmod +x /home/user/vulnerable_cgi
    chown user:user /home/user/vulnerable_cgi

    chmod -R 777 /home/user
