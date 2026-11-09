#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/state.journal
[WAL] start module 12B3
[WAL] commit module 12B3
[WAL] start module 44D8
[WAL] commit module 44D8
[WAL] start module 74A9
[WAL] commit module 74A9
[WAL] start module 99F1
EOF
    dd if=/dev/urandom bs=1 count=50 >> /home/user/state.journal 2>/dev/null

    dd if=/dev/urandom of=/home/user/build_mem.dump bs=1024 count=10 2>/dev/null
    echo -n "SOME_OTHER_DATA... MODULE_ID: 12B3 ERROR_CODE: ERR_OK " >> /home/user/build_mem.dump
    dd if=/dev/urandom bs=1024 count=5 >> /home/user/build_mem.dump 2>/dev/null
    echo -n "MODULE_ID: 74A9 ERROR_CODE: MEM_FAULT_X99_FATAL " >> /home/user/build_mem.dump
    dd if=/dev/urandom bs=1024 count=5 >> /home/user/build_mem.dump 2>/dev/null

    cat << 'EOF' > /home/user/compiler_logs.txt
gcc -c module_12B3.c -o module_12B3.o
gcc -c module_44D8.c -o module_44D8.o
module_44D8.c: In function 'main':
module_44D8.c:12:5: warning: implicit declaration of function 'printf'
gcc -c module_74A9.c -o module_74A9.o
ld: /build/module_74A9.o: in function `process_data':
ld: /build/module_74A9.o: undefined reference to 'InitHardware_v2'
gcc -c module_99F1.c -o module_99F1.o
make: *** [Makefile:10: all] Error 1
EOF

    chmod -R 777 /home/user
