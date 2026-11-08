#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/vuln_auth.c
#include <stdio.h>
#include <string.h>
#include <stdint.h>

struct AuthTicket {
    char username[16];
    char role[16];
    uint32_t checksum;
};

uint32_t compute_checksum(const char *user, const char *role) {
    uint32_t hash = 0x12345678;
    for (int i = 0; i < 16; i++) {
        hash += (unsigned char)user[i];
        hash ^= (unsigned char)role[i];
        hash = (hash << 5) | (hash >> 27);
    }
    return hash;
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <ticket_file>\n", argv[0]);
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("Error opening file.\n");
        return 1;
    }

    struct AuthTicket ticket;
    if (fread(&ticket, 1, sizeof(struct AuthTicket), f) != sizeof(struct AuthTicket)) {
        printf("Invalid ticket size.\n");
        fclose(f);
        return 1;
    }
    fclose(f);

    ticket.username[15] = '\0';
    ticket.role[15] = '\0';

    uint32_t expected = compute_checksum(ticket.username, ticket.role);
    if (ticket.checksum != expected) {
        printf("Authentication failed: invalid checksum.\n");
        return 1;
    }

    if (strcmp(ticket.role, "admin") == 0) {
        printf("Access Granted: admin\n");
        return 0;
    } else {
        printf("Access Denied: %s\n", ticket.role);
        return 1;
    }
}
EOF

    gcc /home/user/vuln_auth.c -o /home/user/vuln_auth
    chmod +x /home/user/vuln_auth

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
