#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip binutils coreutils
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/drop
    cp /bin/true /home/user/drop/payload.elf
    chmod +x /home/user/drop/payload.elf

    cat << 'EOF' > /home/user/process_dump.log
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root           1  0.0  0.0  10348   120 ?        Ss   Jan15   0:05 /sbin/init
user        1023  0.0  0.1  12345  4567 ?        S    10:00   0:00 /bin/bash /opt/start.sh
user        1045  5.2  1.0  54321 12345 ?        R    10:01   0:02 python3 worker.py --verbose --auth-token=sec_t0k3n_99f2a1 --target=/home/user/drop/payload.elf
user        1046  0.0  0.0   4567  1234 ?        S    10:01   0:00 sleep 60
EOF

    chmod -R 777 /home/user
