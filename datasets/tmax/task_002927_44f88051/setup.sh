#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip coreutils bash
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/safe_restore

    cat << 'EOF' > /home/user/incoming/backup.dat
PATH: system/info.txt
B64DATA: U3lzdGVtIGlzIG9wZXJhdGlvbmFsLgo=
PATH: ../../../etc/shadow
B64DATA: ZmFrZV9zaGFkb3dfZGF0YQo=
PATH: web/index.html
B64DATA: PGh0bWw+SGVsbG88L2h0bWw+Cg==
PATH: /var/log/syslog
B64DATA: dGFtcGVyZWQgbG9nCg==
PATH: deep/nested/dir/config.json
B64DATA: eyJrZXkiOiAidmFsdWUifQo=
PATH: safe_but_tricky..txt
B64DATA: Ii4uIiBpcyBub3QgIi4uLyIK
EOF

    chmod -R 777 /home/user
