#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc binutils xxd
    pip3 install pytest

    useradd -m -s /bin/bash user || true
    cd /home/user

    cat << 'EOF' > /home/user/deploy.log
=== DEPLOYMENT ===
Date: 2023-10-27
Status: SUCCESS
File: /home/user/app_v1.bin
User: admin

=== DEPLOYMENT ===
Date: 2023-10-28
Status: FAILED
File: /home/user/bad.bin
User: admin

=== DEPLOYMENT ===
Date: 2023-10-29
Status: SUCCESS
File: /home/user/part_a.gcode
User: operator

=== DEPLOYMENT ===
Date: 2023-10-30
Status: SUCCESS
File: /home/user/local_db.wal
User: system
EOF

    cat << 'EOF' > /home/user/app.c
int main() { return 0; }
EOF
    gcc -o /home/user/app_v1.bin /home/user/app.c
    rm /home/user/app.c

    echo "Not an ELF file" > /home/user/bad.bin

    cat << 'EOF' > /home/user/part_a.gcode
; FLAVOR:Marlin
; TIME:5110
; estimated printing time = 2h 15m 30s
G90
M82
G28
EOF

    python3 -c "open('/home/user/local_db.wal', 'wb').write(b'\x37\x7f\x06\x82\x00\x00\x00\x00\x00\x00\x00\x00')"

    chmod -R 777 /home/user
