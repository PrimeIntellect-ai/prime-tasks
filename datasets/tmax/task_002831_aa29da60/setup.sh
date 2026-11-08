#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip inotify-tools build-essential
    pip3 install pytest

    mkdir -p /app/minitar-0.1 /app/corpora/evil /app/corpora/clean /app/incoming

    cat << 'EOF' > /app/minitar-0.1/untar.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct posix_header {
    char name[100];
    char mode[8];
    char uid[8];
    char gid[8];
    char size[12];
    char mtime[12];
    char chksum[8];
    char typeflag;
    char linkname[100];
    char magic[6];
    char version[2];
    char uname[32];
    char gname[32];
    char devmajor[8];
    char devminor[8];
    char prefix[155];
    char pad[12];
};

int main(int argc, char **argv) {
    if (argc < 4 || strcmp(argv[1], "-x") != 0 || strcmp(argv[2], "-f") != 0) {
        fprintf(stderr, "Usage: %s -x -f <archive>\n", argv[0]);
        return 1;
    }
    const char *archive_name = argv[3];
    FILE *f = fopen(archive_name, "rb");
    if (!f) return 1;

    struct posix_header header;
    while (fread(&header, 1, 512, f) == 512) {
        if (header.name[0] == '\0') break;

        long size = strtol(header.size, NULL, 8);

        if (header.typeflag == '0' || header.typeflag == '\0') {
            FILE *out = fopen(header.name, "wb");
            if (out) {
                char *buf = malloc(size);
                if (buf) {
                    fread(buf, 1, size, f);
                    fwrite(buf, 1, size, out);
                    free(buf);
                }
                fclose(out);
            } else {
                fseek(f, size, SEEK_CUR);
            }
        }

        long padding = (512 - (size % 512)) % 512;
        fseek(f, padding, SEEK_CUR);
    }
    fclose(f);
    printf("ACCEPT: %s\n", archive_name);
    return 0;
}
EOF

    cat << 'EOF' > /app/minitar-0.1/Makefile
minitar: untar.c
	gcc -o minitar untar.c
EOF

    cat << 'EOF' > /tmp/gen_tars.py
import tarfile
import os

os.makedirs('/app/corpora/evil', exist_ok=True)
os.makedirs('/app/corpora/clean', exist_ok=True)

with open('/tmp/dummy', 'wb') as f:
    f.write(b'data')

for i in range(3):
    with tarfile.open(f'/app/corpora/evil/evil_{i}.tar', 'w') as tar:
        ti = tarfile.TarInfo(name=f'../../etc/shadow_{i}')
        ti.size = 4
        with open('/tmp/dummy', 'rb') as f:
            tar.addfile(ti, f)

    with tarfile.open(f'/app/corpora/clean/clean_{i}.tar', 'w') as tar:
        ti = tarfile.TarInfo(name=f'file_{i}.txt')
        ti.size = 4
        with open('/tmp/dummy', 'rb') as f:
            tar.addfile(ti, f)
EOF
    python3 /tmp/gen_tars.py
    rm /tmp/gen_tars.py /tmp/dummy

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
