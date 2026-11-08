#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip openssh-client
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/keys

    cat << 'EOF' > /home/user/auth.log
[2023-10-01 10:00:00] user=alice ip=192.168.1.10 event=SUCCESS
[2023-10-01 10:05:00] user=bob ip=10.0.0.5 event=FAILED
[2023-10-01 10:05:10] user=bob ip=10.0.0.5 event=FAILED
[2023-10-01 10:05:20] user=bob ip=10.0.0.5 event=FAILED
[2023-10-01 10:05:35] user=bob ip=10.0.0.5 event=SUCCESS
[2023-10-01 10:10:00] user=charlie ip=172.16.0.2 event=FAILED
[2023-10-01 10:10:05] user=charlie ip=172.16.0.2 event=FAILED
[2023-10-01 10:10:10] user=charlie ip=172.16.0.2 event=FAILED
[2023-10-01 10:10:15] user=charlie ip=172.16.0.2 event=FAILED
[2023-10-01 10:15:00] user=david ip=192.168.1.10 event=FAILED
[2023-10-01 10:15:02] user=david ip=192.168.1.10 event=FAILED
[2023-10-01 10:15:04] user=david ip=192.168.1.10 event=FAILED
[2023-10-01 10:15:06] user=david ip=192.168.1.10 event=FAILED
[2023-10-01 10:15:08] user=david ip=192.168.1.10 event=SUCCESS
[2023-10-01 10:20:00] user=eve ip=10.0.0.5 event=FAILED
[2023-10-01 10:20:20] user=eve ip=10.0.0.5 event=FAILED
[2023-10-01 10:20:40] user=eve ip=10.0.0.5 event=FAILED
[2023-10-01 10:21:10] user=eve ip=10.0.0.5 event=SUCCESS
EOF

    echo -n "super_secret_key_123" > /home/user/master.secret

    chmod -R 777 /home/user
