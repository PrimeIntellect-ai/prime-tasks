#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc qemu-utils
    pip3 install pytest

    mkdir -p /app/tests/corpus/evil /app/tests/corpus/clean

    # Create the legacy_auth_daemon C source and compile it
    cat << 'EOF' > /tmp/daemon.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void to_upper(char* str) {
    for(int i = 0; str[i]; i++){
        str[i] = toupper(str[i]);
    }
}

int main(int argc, char *argv[]) {
    if (argc < 2) return 0;
    char *input = argv[1];

    char *user_ptr = strstr(input, "\"username\"");
    if (user_ptr) {
        user_ptr = strchr(user_ptr, ':');
        if (user_ptr) {
            user_ptr = strchr(user_ptr, '"');
            if (user_ptr) {
                user_ptr++;
                char *end = strchr(user_ptr, '"');
                if (end && (end - user_ptr > 32)) {
                    abort();
                }
            }
        }
    }

    char *token_ptr = strstr(input, "\"token\"");
    if (token_ptr) {
        char upper_input[4096];
        strncpy(upper_input, input, 4095);
        upper_input[4095] = '\0';
        to_upper(upper_input);
        if (strstr(upper_input, "UNION") || strstr(upper_input, "SELECT") || strstr(upper_input, "DROP") || strstr(upper_input, "--")) {
            abort();
        }
    }

    return 0;
}
EOF

    gcc -O2 -s /tmp/daemon.c -o /app/legacy_auth_daemon
    chmod +x /app/legacy_auth_daemon
    rm /tmp/daemon.c

    # Create dummy qcow2 image
    qemu-img create -f qcow2 /app/backend_vm.qcow2 10M

    # Create corpora
    cat << 'EOF' > /app/tests/corpus/evil/evil1.json
{"username": "this_is_a_very_long_username_that_exceeds_thirty_two_characters", "token": "abc"}
EOF

    cat << 'EOF' > /app/tests/corpus/evil/evil2.json
{"username": "admin", "token": "123' UNION SELECT * FROM users"}
EOF

    cat << 'EOF' > /app/tests/corpus/clean/clean1.json
{"username": "admin", "token": "abcdef123456"}
EOF

    cat << 'EOF' > /app/tests/corpus/clean/clean2.json
{"username": "user", "token": "xyz789"}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
