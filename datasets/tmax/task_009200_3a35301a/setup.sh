#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc
pip3 install pytest

useradd -m -s /bin/bash user || true

mkdir -p /home/user/artifacts

dd if=/dev/urandom of=/home/user/artifacts/app_v1.bin bs=1024 count=1 status=none
dd if=/dev/urandom of=/home/user/artifacts/app_v2_debug.bin bs=2048 count=1 status=none
dd if=/dev/urandom of=/home/user/artifacts/app_v3.bin bs=512 count=1 status=none
dd if=/dev/urandom of=/home/user/artifacts/readme.txt bs=100 count=1 status=none
dd if=/dev/urandom of=/home/user/artifacts/util.bin bs=256 count=1 status=none

cat << 'EOF' > /home/user/clean_manifest.c
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

int main() {
    char *line = NULL;
    size_t len = 0;

    while (getline(&line, &len, stdin) != -1) {
        char *filename = malloc(strlen(line) + 1);
        if (sscanf(line, "%[^,]", filename) == 1) {
            if (strstr(filename, "debug") == NULL) {
                printf("%s", line);
            }
        }
        free(filename);
        free(line); // BUG: freeing line here causes getline to crash on the next iteration
    }
    return 0;
}
EOF

chmod -R 777 /home/user
chmod a-x /home/user/artifacts/readme.txt
chmod a-x /home/user/artifacts/util.bin
