#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/local_bin
    cat << 'EOF' > /home/user/local_bin/perform_backup.sh
#!/bin/bash
DEST=$1
MSG=$2
if [ -z "$DEST" ] || [ -z "$MSG" ]; then
    echo "Usage: $0 <dest> <msg>"
    exit 1
fi
if [ ! -d "$DEST" ]; then
    echo "Error: Destination directory does not exist."
    exit 1
fi
echo "$MSG" > "$DEST/health_status.log"
EOF
    chmod +x /home/user/local_bin/perform_backup.sh

    cat << 'EOF' > /home/user/monitor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    // Health check logic
    int healthy = 1;

    if (healthy) {
        // BUG 1: Hardcoded path, should read from /home/user/custom_fstab for 'monitor_fs'
        char dest_dir[256] = "/tmp/wrong_backup_dir";

        // BUG 2: Relies on PATH, which won't work in this restricted simulation
        char command[512];
        snprintf(command, sizeof(command), "perform_backup.sh %s SYSTEM_HEALTHY", dest_dir);

        int ret = system(command);
        if (ret != 0) {
            fprintf(stderr, "Backup command failed.\n");
            return 1;
        }
        printf("Backup executed successfully.\n");
    }
    return 0;
}
EOF

    chmod -R 777 /home/user
