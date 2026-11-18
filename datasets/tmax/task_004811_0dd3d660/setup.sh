#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc zip tar gzip
    pip3 install pytest

    mkdir -p /home/user/raw_datasets/nested_dir/
    mkdir -p /home/user/clean_datasets/
    mkdir -p /app

    cat << 'EOF' > /tmp/data_filter.c
#include <stdio.h>
#include <string.h>

int main() {
    char buffer[4096];
    size_t len = fread(buffer, 1, sizeof(buffer)-1, stdin);
    buffer[len] = '\0';

    if (strncmp(buffer, "BIOSEQ_v2", 9) == 0 && strchr(buffer, '\t') != NULL) {
        printf("VALID\n");
    } else {
        printf("INVALID\n");
    }
    return 0;
}
EOF

    gcc -O3 -s /tmp/data_filter.c -o /app/data_filter
    chmod +x /app/data_filter

    echo "Junk data" > /home/user/raw_datasets/invalid1.txt

    echo -e "BIOSEQ_v2\tATGC" > /tmp/valid1.txt
    echo -e "BIOSEQ_v2\tCGTA" > /tmp/valid2.txt

    cd /tmp
    zip /home/user/raw_datasets/archive1.zip valid1.txt
    tar -czf /home/user/raw_datasets/nested_dir/archive2.tar.gz valid2.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
