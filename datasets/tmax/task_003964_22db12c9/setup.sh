#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils
    pip3 install pytest

    mkdir -p /app/corpus/clean /app/corpus/evil

    cat << 'EOF' > /tmp/gen_ibk.py
import struct
import gzip
import os

def create_ibk(path, files):
    with gzip.open(path, 'wb') as f:
        for file_path, data, inc_flag in files:
            fp_bytes = file_path.encode('utf-8')
            f.write(b"IBK1")
            f.write(struct.pack("<H", len(fp_bytes)))
            f.write(fp_bytes)
            f.write(struct.pack("<I", len(data)))
            f.write(data)
            f.write(struct.pack("<B", inc_flag))

create_ibk('/app/corpus/clean/c1.ibk.gz', [('test/file1.txt', b'hello', 0)])
create_ibk('/app/corpus/clean/c2.ibk.gz', [('images/logo.png', b'PNG', 0)])
create_ibk('/app/corpus/clean/c3.ibk.gz', [('config.json', b'{}', 0)])
create_ibk('/app/corpus/clean/c4.ibk.gz', [('var/www/html/index.php', b'<?php', 1)])
create_ibk('/app/corpus/clean/c5.ibk.gz', [('safe/path.txt', b'safe', 0)])

create_ibk('/app/corpus/evil/e1.ibk.gz', [('../../etc/passwd', b'root:x', 0)])
create_ibk('/app/corpus/evil/e2.ibk.gz', [('/var/log/syslog', b'log', 0)])
create_ibk('/app/corpus/evil/e3.ibk.gz', [('safe/dir/../../../root/secret', b'secret', 0)])
create_ibk('/app/corpus/evil/e4.ibk.gz', [('test/..\\..\\windows\\system32', b'win', 0)])
create_ibk('/app/corpus/evil/e5.ibk.gz', [('dir/..', b'dir', 0)])
EOF

    python3 /tmp/gen_ibk.py

    cat << 'EOF' > /tmp/restorer.c
#include <stdio.h>
int main() {
    printf("Dummy restorer\n");
    return 0;
}
EOF

    gcc /tmp/restorer.c -o /app/restorer
    strip /app/restorer

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
