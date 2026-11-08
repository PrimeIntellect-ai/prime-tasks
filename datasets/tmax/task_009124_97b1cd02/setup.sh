#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/repo/docs
    mkdir -p /home/user/repo/config
    mkdir -p /home/user/repo/links

    cat << 'EOF' > /home/user/curator.json
{
  "extensions": [".txt", ".conf"],
  "source_encoding": "windows-1252",
  "target_encoding": "utf-8"
}
EOF

    python3 -c '
with open("/home/user/repo/config/settings.conf", "wb") as f:
    f.write(b"System configuration\nMax connections: 100\nAuthor: Ren\xe9")
with open("/home/user/repo/docs/readme.txt", "wb") as f:
    f.write(b"Documentation for v1.0\nIt \x93works\x94 well.")
with open("/home/user/repo/docs/ignore.log", "wb") as f:
    f.write(b"Ignore this file")
'

    ln -s /home/user/repo/links /home/user/repo/links/loop
    ln -s /home/user/repo/config /home/user/repo/links/cfg_link

    chown -R user:user /home/user/repo /home/user/curator.json
    chmod -R 777 /home/user
