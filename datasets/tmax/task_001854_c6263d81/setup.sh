#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    mkdir -p /home/user

    cat << 'EOF' > /home/user/auth_requests.log
[2023-10-25] GET /auth?user=admin&pwd=SuperSecret1!&redirect=https://evil.com HTTP/1.1
[2023-10-25] GET /auth?user=jdoe&pwd=MyPassword123&redirect=/dashboard HTTP/1.1
[2023-10-26] GET /auth?pwd=password&user=guest HTTP/1.1
EOF

    cat << 'EOF' > /home/user/auth_cgi.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void log_access(const char *user) {
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "echo 'Access by %s' >> /home/user/access.log", user);
    system(cmd);
}

int main(int argc, char *argv[]) {
    char *query = getenv("QUERY_STRING");
    if (!query) return 0;

    char user[50] = {0};
    char redirect[100] = {0};

    char *u_ptr = strstr(query, "user=");
    if (u_ptr) sscanf(u_ptr + 5, "%49[^& ]", user);

    char *r_ptr = strstr(query, "redirect=");
    if (r_ptr) sscanf(r_ptr + 9, "%99[^& ]", redirect);

    log_access(user);

    printf("Content-Type: text/html\n");
    if (strlen(redirect) > 0) {
        printf("Location: %s\n", redirect);
    }
    printf("\n");
    printf("<html><body>Login Processed</body></html>\n");
    return 0;
}
EOF

    chmod 644 /home/user/auth_requests.log
    chmod 644 /home/user/auth_cgi.c

    chmod -R 777 /home/user
