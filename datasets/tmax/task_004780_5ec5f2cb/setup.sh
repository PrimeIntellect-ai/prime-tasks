#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils strace ltrace
    pip3 install pytest

    mkdir -p /app
    cat << 'EOF' > /tmp/oracle.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    char line[2048];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        char *ts = strtok(line, ",");
        char *ip = strtok(NULL, ",");
        char *uid_s = strtok(NULL, ",");
        char *pid_s = strtok(NULL, ",");
        char *cmd = strtok(NULL, ""); 

        if (!ts || !ip || !uid_s || !pid_s || !cmd) continue;

        int uid = atoi(uid_s);

        if (uid == 0 && (strstr(cmd, "password=") || strstr(cmd, "token="))) {
            printf("LEAK|%s|%s\n", pid_s, ip);
        }
        if (uid != 0 && (strstr(cmd, "/etc/shadow") || strstr(cmd, "/etc/passwd"))) {
            printf("ESCALATION|%s|%d\n", pid_s, uid);
        }
    }
    return 0;
}
EOF

    gcc -O2 /tmp/oracle.c -o /app/audit_filter
    strip /app/audit_filter
    rm /tmp/oracle.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
