#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc e2fsprogs extundelete
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app
    mkdir -p /home/user/monitor_env/libs
    mkdir -p /home/user/monitor_env/config

    # Create libraries
    cat << 'EOF' > /tmp/lib1.c
#include <stdio.h>
void calc_uptime() {
    printf("Uptime: 99999\n");
}
EOF

    cat << 'EOF' > /tmp/lib2.c
#include <stdio.h>
void calc_uptime_v2() {
    printf("Uptime v2\n");
}
EOF

    gcc -shared -fPIC /tmp/lib1.c -o /home/user/monitor_env/libs/libuptime_calc.so.1
    gcc -shared -fPIC /tmp/lib2.c -o /home/user/monitor_env/libs/libuptime_calc.so.2

    # Create binary
    cat << 'EOF' > /tmp/main.c
#include <stdio.h>
#include <unistd.h>

extern void calc_uptime();

int main() {
    FILE *f = fopen("/home/user/monitor_env/config/settings.bin", "r");
    if (!f) {
        fprintf(stderr, "Error: settings.bin not found\n");
        return 1;
    }
    fclose(f);
    usleep(100000);
    calc_uptime();
    return 0;
}
EOF

    ln -sf /home/user/monitor_env/libs/libuptime_calc.so.1 /home/user/monitor_env/libs/libuptime_calc.so
    gcc /tmp/main.c -L/home/user/monitor_env/libs -luptime_calc -Wl,-rpath=/home/user/monitor_env/libs -o /app/uptime_monitor
    strip /app/uptime_monitor

    # Break the symlink to point to the wrong library version
    ln -sf /home/user/monitor_env/libs/libuptime_calc.so.2 /home/user/monitor_env/libs/libuptime_calc.so

    # Create disk image with deleted file
    dd if=/dev/zero of=/home/user/monitor_env/disk_image.img bs=1M count=10
    mkfs.ext4 -F /home/user/monitor_env/disk_image.img
    echo "UPTIME_SEED=42" > /tmp/settings.bin
    debugfs -w -R "write /tmp/settings.bin settings.bin" /home/user/monitor_env/disk_image.img
    debugfs -w -R "rm settings.bin" /home/user/monitor_env/disk_image.img

    chmod -R 777 /home/user
    chmod -R 777 /app
