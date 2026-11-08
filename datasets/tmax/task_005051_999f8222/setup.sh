#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libc-dev gawk coreutils
    pip3 install pytest

    # Create the mlist_compiler binary
    mkdir -p /app
    cat << 'EOF' > /tmp/compiler.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void compute_hash(const char *line, unsigned char *out) {
    unsigned long hash = 5381;
    int c;
    for (int i=0; i<1000; i++) {
        const char *p = line;
        while ((c = *p++)) {
            hash = ((hash << 5) + hash) + c; 
        }
    }
    memset(out, 0, 64);
    memcpy(out, &hash, sizeof(hash));
}

int main(int argc, char *argv[]) {
    if (argc != 3) return 1;
    FILE *fin = fopen(argv[1], "r");
    if (!fin) return 1;
    FILE *fout = fopen(argv[2], "wb");
    if (!fout) return 1;

    char line[256];
    unsigned char out[64];
    while (fgets(line, sizeof(line), fin)) {
        compute_hash(line, out);
        fwrite(out, 1, 64, fout);
    }
    fclose(fin);
    fclose(fout);
    return 0;
}
EOF
    gcc -O2 -o /app/mlist_compiler /tmp/compiler.c
    strip /app/mlist_compiler
    rm /tmp/compiler.c

    # Create user and directories
    useradd -m -s /bin/bash user || true
    mkdir -p /home/user/incoming
    mkdir -p /home/user/deployments/releases/v202309

    # Generate dummy routes
    awk 'BEGIN { for(i=1; i<=100000; i++) print "user" i "@example.com route" i }' > /home/user/incoming/routes.txt

    # Setup dummy previous release and symlink
    touch /home/user/deployments/releases/v202309/routes.db
    ln -s /home/user/deployments/releases/v202309 /home/user/deployments/current

    chmod -R 777 /home/user
