#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc make
    pip3 install pytest

    mkdir -p /home/user/src

    cat << 'EOF' > /home/user/src/session_parser.c
#include <string.h>
#include <stdlib.h>

typedef struct {
    int user_id;
    char username[16];
    int is_admin;
} Session;

int parse_session(const char* payload, Session* out_session) {
    char buffer[32];
    strcpy(buffer, payload);

    char* token = strtok(buffer, ",");
    if (!token) return -1;
    out_session->user_id = atoi(token);

    token = strtok(NULL, ",");
    if (!token) return -1;
    strncpy(out_session->username, token, 15);
    out_session->username[15] = '\0';

    token = strtok(NULL, ",");
    if (!token) return -1;
    out_session->is_admin = atoi(token);

    return 0;
}
EOF

    cat << 'EOF' > /home/user/src/Makefile
all:
	gcc -shared -fPIC -fvisibility=hidden -o libsession.so session_parser.c
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
