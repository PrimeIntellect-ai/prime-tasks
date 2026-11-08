#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/logs.csv
U001,RES_A
U002,RES_B
U003,RES_C
U001,RES_C
U004,RES_D
U005,RES_E
EOF

    cat << 'EOF' > /home/user/perms.csv
U001,RES_A,1
U002,RES_B,1
U003,RES_C,0
U001,RES_C,1
U004,RES_D,0
EOF

    cat << 'EOF' > /home/user/audit.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char user_id[20];
    char resource_id[20];
} Log;

typedef struct {
    char user_id[20];
    char resource_id[20];
    int granted;
} Perm;

int main() {
    FILE *f_logs = fopen("/home/user/logs.csv", "r");
    FILE *f_perms = fopen("/home/user/perms.csv", "r");

    Log logs[100];
    Perm perms[100];
    int num_logs = 0, num_perms = 0;

    while(fscanf(f_logs, "%19[^,],%19[^\n]\n", logs[num_logs].user_id, logs[num_logs].resource_id) == 2) {
        num_logs++;
    }

    while(fscanf(f_perms, "%19[^,],%19[^,],%d\n", perms[num_perms].user_id, perms[num_perms].resource_id, &perms[num_perms].granted) == 3) {
        num_perms++;
    }

    fclose(f_logs);
    fclose(f_perms);

    // BUG: Implicit cross join, no mapping keys verified!
    for(int i = 0; i < num_logs; i++) {
        for(int j = 0; j < num_perms; j++) {
            if(perms[j].granted == 0) {
                printf("%s,%s\n", logs[i].user_id, logs[i].resource_id);
            }
        }
    }

    return 0;
}
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
