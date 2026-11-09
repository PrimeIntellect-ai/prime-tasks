#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs binutils gdb
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /tmp/logger_bin.c
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#pragma pack(push, 1)
struct CrashLog {
    uint32_t magic;
    uint32_t error_code;
    char message[16];
};
#pragma pack(pop)

int main() {
    struct CrashLog log;
    log.magic = 0xDEADBEEF;
    log.error_code = 331; // Ground truth error code
    strncpy(log.message, "SEGFAULT_CORE_0", 16);

    FILE *f = fopen("crash.dat", "wb");
    if(f) {
        fwrite(&log, sizeof(struct CrashLog), 1, f);
        fclose(f);
    }
    return 0;
}
EOF

    gcc /tmp/logger_bin.c -o /home/user/logger_bin

    mkdir -p /tmp/fs_stage
    cd /tmp/fs_stage
    /home/user/logger_bin

    dd if=/dev/zero of=/home/user/diag_fs.img bs=1M count=10
    mke2fs -F -t ext4 -d /tmp/fs_stage /home/user/diag_fs.img

    debugfs -w -R "rm crash.dat" /home/user/diag_fs.img

    rm -rf /tmp/fs_stage /tmp/logger_bin.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
