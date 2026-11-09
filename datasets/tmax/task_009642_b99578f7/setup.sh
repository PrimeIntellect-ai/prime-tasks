#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc gdb
    pip3 install pytest

    mkdir -p /home/user

    cat << 'EOF' > /home/user/legacy_auth.c
#include <stdio.h>
#include <stdlib.h>

void process_record(int uid) {
    int multiplier = 1000000;
    int hash = uid * multiplier;

    // Bug: 32-bit signed integer overflow makes hash negative for large positive uids.
    if (hash < 0) {
        // Artificially crash to simulate severe memory corruption
        int *ptr = NULL;
        *ptr = 0xDEAD;
    } else {
        printf("Record %d processed. Hash: %d\n", uid, hash);
    }
}

int main(int argc, char *argv[]) {
    if(argc < 2) return 1;
    int uid = atoi(argv[1]);
    process_record(uid);
    return 0;
}
EOF

    gcc -O0 -o /home/user/legacy_auth /home/user/legacy_auth.c

    cat << 'EOF' > /home/user/run_batch.py
#!/usr/bin/env python3
import subprocess
import sys

with open('/home/user/users.txt', 'r') as f:
    for line in f:
        uid = line.strip()
        if not uid: continue
        res = subprocess.run(['/home/user/legacy_auth', uid])
        if res.returncode != 0:
            print(f"Error processing {uid}! Program crashed with code {res.returncode}.", file=sys.stderr)
            sys.exit(1)
EOF
    chmod +x /home/user/run_batch.py

    cat << 'EOF' > /home/user/users.txt
10
450
1999
2147
2899
3500
5000
EOF

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user
    chmod -R 777 /home/user
