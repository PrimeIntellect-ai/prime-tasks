#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc tar gawk sed grep coreutils
pip3 install pytest

mkdir -p /home/user/artifacts

python3 -c '
import os
with open("/home/user/artifacts/libalpha.so", "wb") as f:
    f.write(b"head data \xDE\xAD\xBE\xEF\xCF\xFA\xED\xFE tail data\n")
with open("/home/user/artifacts/libbeta.so", "wb") as f:
    f.write(b"head data \x01\x02\x03\x04 tail data\n")
with open("/home/user/artifacts/libgamma.so", "wb") as f:
    f.write(b"random \xDE\xAD\xBE\xEF\xCF\xFA\xED\xFE more \xDE\xAD\xBE\xEF\xCF\xFA\xED\xFE end\n")
with open("/home/user/artifacts/libdelta.so", "wb") as f:
    f.write(b"clean \xAA\xBB\xCC end\n")
'

touch -t 202301010000 /home/user/artifacts/*

cat << 'EOF' > /home/user/manifest.raw
ArtifactName | Version | Architecture | Status
libalpha.so | 1.0.0 | x86_64 | NEEDS_PATCH
libbeta.so | 1.1.0 | x86_64 | OK
libgamma.so | 2.0.0 | arm64 | NEEDS_PATCH
libdelta.so | 1.0.0 | arm64 | OK
EOF

cd /home/user
tar --listed-incremental=/home/user/backup_snapshot.snar -cvf /home/user/base.tar artifacts/

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
