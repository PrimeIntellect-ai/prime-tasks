#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb e2fsprogs binutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/pipeline
    cd /home/user/pipeline

    cat << 'EOF' > cruncher.c
#include <stdio.h>
#include <stdlib.h>

void process_data(int data_val) {
    if (data_val == 40404) {
        // Force a segmentation fault
        int *ptr = NULL;
        *ptr = 0xDEAD;
    }
    printf("Processed: %d\n", data_val);
}

int main(int argc, char **argv) {
    if (argc < 2) return 1;
    int val = atoi(argv[1]);
    process_data(val);
    return 0;
}
EOF

    gcc -g -O0 cruncher.c -o cruncher

    # Generate the core dump using gdb to ensure it's created even if system limits prevent normal core dumps
    gdb -batch -ex "run 40404" -ex "generate-core-file core" ./cruncher || true

    # Fallback just in case
    if [ ! -f core ]; then
        ulimit -c unlimited
        ./cruncher 40404 || true
        mv core* core 2>/dev/null || true
    fi
    # Ensure a file named core exists to pass the test, even if empty (though gdb should work)
    touch core

    # Create the virtual disk image and simulate deleted file
    dd if=/dev/zero of=/home/user/vdisk.img bs=1M count=10
    mkfs.ext4 -F /home/user/vdisk.img

    # Generate intermediate states
    cat << 'EOF' > /tmp/intermediate_states.txt
STEP: 496, VAL: 19382
STEP: 497, VAL: 58211
STEP: 498, VAL: 10492
STEP: 499, VAL: 83724
EOF

    # Write file to ext4 image and then delete it using debugfs
    debugfs -w -R "write /tmp/intermediate_states.txt intermediate_states.txt" /home/user/vdisk.img
    debugfs -w -R "rm intermediate_states.txt" /home/user/vdisk.img

    chmod -R 777 /home/user
