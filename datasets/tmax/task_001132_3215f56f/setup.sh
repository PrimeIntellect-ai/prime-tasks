#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /home/user/export.txt
RECORD ID:001 | STATUS:OK | FILE:boot.bin | PAYLOAD:AAECAwQFBgcICQ==
RECORD ID:002 | STATUS:FAIL | FILE:kernel.bin | PAYLOAD:c29tZWJhc2U2NA==
RECORD ID:003 | STATUS:OK | FILE:readme.txt | PAYLOAD:SGVsbG8gV29ybGQh
RECORD ID:004 | STATUS:OK | FILE:lib.bin | PAYLOAD:Z29vZGJ5ZQ==
RECORD ID:005 | STATUS:OK | FILE:app.bin | PAYLOAD:dGVzdHBheWxvYWQ=
RECORD ID:006 | STATUS:OK | FILE:system.bin | PAYLOAD:YW5vdGhlcmJpbg==
RECORD ID:007 | STATUS:CORRUPT | FILE:data.bin | PAYLOAD:YmFkZGF0YQ==
EOF

chmod -R 777 /home/user
