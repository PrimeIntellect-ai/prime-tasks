#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils parallel
pip3 install pytest

mkdir -p /app
cat << 'EOF' > /tmp/sig.c
#include <stdio.h>

int main(int argc, char *argv[]) {
    if (argc < 2) return 1;
    FILE *f = fopen(argv[1], "rb");
    if (!f) return 1;
    unsigned char buf[6];
    if (fread(buf, 1, 6, f) != 6) { fclose(f); return 1; }
    fclose(f);
    if (buf[0] == 0x43 && buf[1] == 0x46 && buf[2] == 0x47 && buf[3] == 0x21 && buf[4] == 0x02 && buf[5] == 0x00) return 0;
    return 1;
}
EOF
gcc -O2 -o /app/legacy_sig_check /tmp/sig.c
strip /app/legacy_sig_check
rm /tmp/sig.c

mkdir -p /app/corpus/clean
mkdir -p /app/corpus/evil

# Clean files
printf "CFG!\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname rtr1\nDeviceType: core-router\n" > /app/corpus/clean/c1.conf
printf "CFG!\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname sw1\nDeviceType: switch\n" > /app/corpus/clean/c2.conf

# Evil files
printf "CFG?\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname rtr1\nDeviceType: core-router\n" > /app/corpus/evil/e1.conf
printf "CFG!\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname rtr1\nDeviceType: core-router\n" > /app/corpus/evil/e2.conf
printf "CFG!\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname rtr1\nDeviceType: core-router\npassword 7 0123\n" > /app/corpus/evil/e3.conf
printf "CFG!\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00DeviceType: core-router\n" > /app/corpus/evil/e4.conf
printf "CFG!\x02\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00hostname rtr1\n" > /app/corpus/evil/e5.conf

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
