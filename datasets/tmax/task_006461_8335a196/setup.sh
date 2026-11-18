#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest websockets

    mkdir -p /home/user

    cat << 'EOF' > /home/user/ldd_dump.txt
[libfront.so]
    linux-vdso.so.1 =>  (0x00007ffe3b1bc000)
    libmiddle_a.so => /usr/lib/libmiddle_a.so (0x00007f3c0a5d4000)
    libmiddle_b.so => /usr/lib/libmiddle_b.so (0x00007f3c0a5d4000)
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f3c0a3e2000)
[libmiddle_a.so]
    libhelper.so => /usr/lib/libhelper.so (0x00007f3c0a5d4000)
[libmiddle_b.so]
    libbase.so => /usr/lib/libbase.so (0x00007f3c0a5d4000)
[libhelper.so]
    libbase.so => /usr/lib/libbase.so (0x00007f3c0a5d4000)
[libbase.so]
    libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f3c0a3e2000)
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
