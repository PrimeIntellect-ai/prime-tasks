#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/data_mount

    cat << 'EOF' > /home/user/user_fstab
/home/user/data_mount 1000

/home/user/backup_mount 500
EOF

    cat << 'EOF' > /home/user/setup_env.sh
#!/bin/bash
# Prepares the environment mounts
mkdir /home/user/data_mount
mkdir /home/user/backup_mount
exit 0
EOF
    chmod +x /home/user/setup_env.sh

    cat << 'EOF' > /home/user/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    FILE *fp = fopen("/home/user/user_fstab", "r");
    if (!fp) {
        perror("Failed to open fstab");
        return 1;
    }

    char line[256];
    while (fgets(line, sizeof(line), fp)) {
        char *path = strtok(line, " \n");
        char *quota_str = strtok(NULL, " \n");

        // BUG: if line is empty, path is NULL. strtok(NULL) fails, atoi(NULL) segfaults.
        int quota = atoi(quota_str); 

        printf("Monitored mount: %s with quota %d\n", path, quota);
    }

    fclose(fp);
    printf("Storage monitor initialization complete.\n");
    return 0;
}
EOF

    cat << 'EOF' > /home/user/start_service.sh
#!/bin/bash

/home/user/setup_env.sh
/home/user/monitor
EOF
    chmod +x /home/user/start_service.sh

    chmod -R 777 /home/user
