#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc coreutils tar
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/hasher.c
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char *argv[]) {
    if (argc != 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    unsigned long long hash = 0x1234567890ABCDEF;
    int c, count = 0;
    while ((c = fgetc(f)) != EOF && count < 100) {
        hash ^= (unsigned long long)c << ((count % 8) * 8);
        count++;
    }
    fclose(f);
    printf("%016llx\n", hash);
    return 0;
}
EOF
gcc -O2 -s -o /app/doc_hasher /tmp/hasher.c
rm /tmp/hasher.c

mkdir -p /tmp/raw_docs/dir1
mkdir -p /tmp/raw_docs/dir2/subdir
mkdir -p /tmp/raw_docs/dir3

echo "Doc-Title: Architecture Plan" > /tmp/raw_docs/dir1/docA.txt
echo "Doc-Title: API Reference V2" > /tmp/raw_docs/dir2/subdir/docB.txt
echo "Doc-Title: Database Schema" > /tmp/raw_docs/dir3/massive.txt
dd if=/dev/urandom bs=1M count=37 status=none | base64 >> /tmp/raw_docs/dir3/massive.txt

useradd -m -s /bin/bash user || true

cd /tmp/raw_docs
tar -czf /home/user/raw_docs.tar.gz .
cd /
rm -rf /tmp/raw_docs

chmod -R 777 /home/user
