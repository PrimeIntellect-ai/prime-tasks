#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip gawk coreutils
    pip3 install pytest pyelftools pyyaml

    useradd -m -s /bin/bash user || true

    # Create initial config
    cat << 'EOF' > /home/user/config.json
{
  "host": "localhost",
  "debug": "false"
}
EOF

    # Create dummy firmware
    cat << 'EOF' > /tmp/dummy.c
#include <stdio.h>
int main() {
    printf("Firmware boot\n");
    return 0;
}
EOF
    gcc -o /tmp/firmware.elf /tmp/dummy.c

    # Create WAL file
    cat << 'EOF' > /tmp/changes.wal
3:SET:timeout:30
1:SET:retries:5
4:DELETE:debug
2:SET:debug:true
EOF

    # Zip the files
    cd /tmp
    zip /home/user/update.zip firmware.elf changes.wal

    # Generate SHA256 checksum
    sha256sum /home/user/update.zip | awk '{print $1}' > /home/user/update.zip.sha256

    # Fix permissions
    chown -R user:user /home/user/
    chmod -R 777 /home/user
