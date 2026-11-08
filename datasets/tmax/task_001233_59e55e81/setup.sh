#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo gcc binutils
    pip3 install pytest

    mkdir -p /app

    # Python implementations of the packer and unpacker
    cat << 'EOF' > /app/.packer.py
import sys, os, hashlib, struct

def pack(in_dir, out_file):
    with open(out_file, 'wb') as f:
        f.write(b'BKP1')
        for root, dirs, files in os.walk(in_dir):
            for file in files:
                filepath = os.path.join(root, file)
                if os.path.islink(filepath):
                    continue
                relpath = os.path.relpath(filepath, in_dir)
                with open(filepath, 'rb') as inf:
                    data = inf.read()
                f.write(struct.pack('<H', len(relpath)))
                f.write(relpath.encode('utf-8'))
                f.write(struct.pack('<I', len(data)))
                f.write(data)
                f.write(hashlib.sha256(data).digest())

if __name__ == '__main__':
    pack(sys.argv[1], sys.argv[2])
EOF

    cat << 'EOF' > /app/.unpacker.py
import sys, os, hashlib, struct

def unpack(in_file, out_dir):
    with open(in_file, 'rb') as f:
        magic = f.read(4)
        if magic != b'BKP1': sys.exit(1)
        while True:
            l_b = f.read(2)
            if not l_b: break
            l = struct.unpack('<H', l_b)[0]
            relpath = f.read(l).decode('utf-8')
            sz = struct.unpack('<I', f.read(4))[0]
            data = f.read(sz)
            csum = f.read(32)
            out_path = os.path.join(out_dir, relpath)
            os.makedirs(os.path.dirname(out_path), exist_ok=True)
            with open(out_path, 'wb') as outf:
                outf.write(data)

if __name__ == '__main__':
    unpack(sys.argv[1], sys.argv[2])
EOF

    # C wrappers to provide ELF binaries
    cat << 'EOF' > /app/packer.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/.packer.py \"%s\" \"%s\"", argv[1], argv[2]);
    return system(cmd);
}
EOF

    cat << 'EOF' > /app/unpacker.c
#include <stdlib.h>
#include <stdio.h>
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    char cmd[2048];
    snprintf(cmd, sizeof(cmd), "python3 /app/.unpacker.py \"%s\" \"%s\"", argv[1], argv[2]);
    return system(cmd);
}
EOF

    gcc /app/packer.c -o /app/legacy_packer
    gcc /app/unpacker.c -o /app/legacy_unpacker
    strip /app/legacy_packer /app/legacy_unpacker
    rm /app/packer.c /app/unpacker.c

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/corpus/clean
    mkdir -p /home/user/corpus/evil

    for i in 1 2 3 4 5; do
        mkdir -p /home/user/corpus/clean/dir$i
        echo "clean data $i" > /home/user/corpus/clean/dir$i/file.txt
        mkdir -p /home/user/corpus/evil/dir$i
        ln -s ../../../../../etc/passwd /home/user/corpus/evil/dir$i/link
    done

    chmod -R 777 /home/user
