#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/evidence

    cat << 'EOF' > /home/user/evidence/auth_checker.c
#include <stdio.h>
#include <string.h>

// Returns 1 if admin, 0 otherwise
int check_auth(const char *username, const char *password) {
    int is_admin = 0;
    char user_buf[16];

    // Vulnerability: buffer overflow can overwrite is_admin
    strcpy(user_buf, username);

    if (strcmp(user_buf, "admin") == 0 && strcmp(password, "supersecret") == 0) {
        is_admin = 1;
    }

    return is_admin;
}

int main(int argc, char **argv) {
    if (argc != 3) {
        printf("Usage: %s <username> <password>\n", argv[0]);
        return 1;
    }
    if (check_auth(argv[1], argv[2])) {
        printf("Admin access granted.\n");
        return 0;
    }
    printf("Access denied.\n");
    return 1;
}
EOF

    cat << 'EOF' > /home/user/evidence/syslog
Oct 14 10:11:02 host auth_checker: Login attempt by user 'johndoe' from IP 192.168.1.50
Oct 14 10:12:05 host auth_checker: Login attempt by user 'admin' from IP 192.168.1.51
Oct 14 10:13:45 host auth_checker: Login attempt by user 'guest' from IP 10.0.5.22
Oct 14 10:15:22 host auth_checker: Login attempt by user 'administrator' from IP 192.168.1.50
Oct 14 10:18:01 host auth_checker: Login attempt by user 'AAAAAAAAAAAAAAAAB' from IP 10.13.37.100
Oct 14 10:20:12 host auth_checker: Login attempt by user 'root' from IP 192.168.1.55
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
