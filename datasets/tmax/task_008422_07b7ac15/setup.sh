#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc expect curl supervisor openssl
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/users.csv
alice,engineering
bob,sales
charlie,hr
EOF

    cat << 'EOF' > /home/user/user_prov.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char user[50];
    char dept[50];
    printf("Enter username: ");
    fflush(stdout);
    if(scanf("%49s", user) != 1) return 1;
    printf("Enter department: ");
    fflush(stdout);
    if(scanf("%49s", dept) != 1) return 1;

    char filename[100];
    snprintf(filename, sizeof(filename), "%s_profile.txt", user);
    FILE *f = fopen(filename, "w");
    if(f) {
        fprintf(f, "USER:%s\nDEPT:%s\nSTATUS:ACTIVE\n", user, dept);
        fclose(f);
        printf("Profile created.\n");
    }
    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
