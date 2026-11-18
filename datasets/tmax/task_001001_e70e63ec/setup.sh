#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip e2fsprogs strace gcc binutils gdb
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # 1. Create the ext4 image
    dd if=/dev/zero of=/home/user/usb.img bs=1M count=10
    /sbin/mkfs.ext4 -F /home/user/usb.img

    # 2. Create the plaintext and encrypt it
    echo -n "FLAG{d3bugfs_str4c3_m4st3r}" > /tmp/plain.txt
    python3 -c '
key = b"S3cr3t"
with open("/tmp/plain.txt", "rb") as f: d=f.read()
out = bytes([d[i] ^ key[i % len(key)] for i in range(len(d))])
with open("/tmp/cipher.bin", "wb") as f: f.write(out)
'

    # 3. Add to image and delete it to simulate attacker behavior
    debugfs -w -R "write /tmp/cipher.bin payload.enc" /home/user/usb.img
    debugfs -w -R "rm payload.enc" /home/user/usb.img

    # 4. Create the C binary
    cat << 'EOF' > /home/user/decryptor.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <payload>\n", argv[0]);
        return 1;
    }

    FILE *fk = fopen("/home/user/.local/share/key.txt", "rb");
    if (!fk) {
        printf("Initialization failed.\n");
        return 1;
    }

    char key[32] = {0};
    fread(key, 1, 31, fk);
    fclose(fk);

    if (strncmp(key, "S3cr3t", 6) != 0) {
        printf("Invalid configuration.\n");
        return 1;
    }

    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        printf("Payload not found.\n");
        return 1;
    }

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *buf = malloc(sz);
    fread(buf, 1, sz, f);
    fclose(f);

    for(long i=0; i<sz; i++) {
        buf[i] ^= key[i % 6];
    }

    FILE *out = fopen("/home/user/flag_decoded.txt", "wb");
    fwrite(buf, 1, sz, out);
    fclose(out);
    printf("Decoded successfully.\n");
    return 0;
}
EOF

    gcc -O2 /home/user/decryptor.c -o /home/user/decryptor
    rm /home/user/decryptor.c
    rm /tmp/plain.txt /tmp/cipher.bin

    chown user:user /home/user/usb.img /home/user/decryptor
    chmod -R 777 /home/user
