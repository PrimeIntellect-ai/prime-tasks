#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    mkdir -p /home/user/app/
    mkdir -p /home/user/workspace/

    cat << 'EOF' > /home/user/app/config.env
# BROKEN CONFIG
SHARED_DIR=/tmp/isolated_logs_broken
LOG_MODE=text
EOF

    cat << 'EOF' > /home/user/app/start_services.sh
#!/bin/bash
source /home/user/app/config.env
# Agent needs to ensure SHARED_DIR exists
if [ ! -d "$SHARED_DIR" ]; then
    echo "Error: Shared directory not found!"
    exit 1
fi
# Mocks (in reality these would be backgrounded scripts created in the setup)
touch "$SHARED_DIR/generator.bin"
echo "Services started."
EOF
    chmod +x /home/user/app/start_services.sh

    cat << 'EOF' > /home/user/app/oracle_source.c
#include <stdio.h>
#include <stdint.h>

int main() {
    uint32_t ts;
    uint16_t id;
    uint16_t sev;
    while (fread(&ts, 4, 1, stdin) == 1 &&
           fread(&id, 2, 1, stdin) == 1 &&
           fread(&sev, 2, 1, stdin) == 1) {
        printf("ALERT: %u at %u with severity %u\n", id, ts, sev);
    }
    return 0;
}
EOF
    gcc /home/user/app/oracle_source.c -o /home/user/app/oracle_parser
    rm /home/user/app/oracle_source.c
    chmod +x /home/user/app/oracle_parser

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
