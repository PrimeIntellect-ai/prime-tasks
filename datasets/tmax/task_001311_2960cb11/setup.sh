#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 socat netcat-openbsd gcc libc6-dev
    pip3 install pytest

    mkdir -p /home/user/data
    cat << 'EOF' > /home/user/data/nodes.csv
node_id,type
A,User
B,User
C,User
D,User
E,User
EOF

    cat << 'EOF' > /home/user/data/edges.csv
source,target,weight
A,B,10.0
B,C,5.0
A,D,8.0
D,C,12.0
C,E,20.0
B,E,15.0
EOF

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *f = fopen(argv[1], "r");
    if (!f) return 1;
    char *target_node = argv[2];
    char line[256];
    double total = 0;
    while (fgets(line, sizeof(line), f)) {
        char *src = strtok(line, ",");
        char *tgt = strtok(NULL, ",");
        char *w_str = strtok(NULL, ",");
        if (src && tgt && w_str) {
            if (strcmp(src, target_node) == 0) {
                total += atof(w_str);
            }
        }
    }
    fclose(f);
    printf("%.2f\n", total * 1.5);
    return 0;
}
EOF
    gcc -O2 -s /tmp/oracle.c -o /app/score_oracle
    chmod +x /app/score_oracle

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
