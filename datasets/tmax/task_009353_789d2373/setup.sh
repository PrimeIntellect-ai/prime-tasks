#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/
    cat << 'EOF' > /home/user/fstab_mock
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/sda1       /               ext4    errors=remount-ro 0       1
/dev/sdb1       /mnt/data       xfs     defaults        0       2
/dev/mapper/backup_vol /home/user/secure_backups ext4 defaults 0 2
/dev/sdc1       /mnt/usb        vfat    noauto,user     0       0
EOF

    cat << 'EOF' > /home/user/flappy.py
#!/usr/bin/env python3
import sys
import time
import random

# Emits random log lines to stdout rapidly, then crashes
start_time = time.time()
while True:
    print(f"[{time.time()}] INFO: Processing data chunk {random.randint(1000, 9999)}")
    sys.stdout.flush()
    time.sleep(0.1)
    if time.time() - start_time > random.uniform(1.0, 3.0):
        print("FATAL ERROR: Memory corruption detected!")
        sys.exit(1)
EOF
    chmod +x /home/user/flappy.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
