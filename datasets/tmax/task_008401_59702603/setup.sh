#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/docs/v1
    mkdir -p /home/user/docs/v2

    # Create infinite symlink loop
    ln -s /home/user/docs/v2 /home/user/docs/latest
    ln -s /home/user/docs/v1 /home/user/docs/v2/prev
    ln -s /home/user/docs/v2 /home/user/docs/v1/next

    # Encode texts to TechDocZ format
    python3 -c '
import base64
def encode_tdz(text):
    b = text.encode("utf-8")
    b = bytes([x + 1 for x in b])
    return base64.b64encode(b).decode("utf-8")

with open("/home/user/docs/v1/doc_A.tdz", "w") as f:
    f.write(encode_tdz("System Architecture Overview"))
with open("/home/user/docs/v2/doc_B.tdz", "w") as f:
    f.write(encode_tdz("API Integration Guidelines"))
with open("/home/user/docs/v1/doc_C.tdz", "w") as f:
    f.write(encode_tdz("Do not read this"))
'

    # Create backup log
    cat <<EOF > /home/user/backup.log
===RECORD START===
Target: /home/user/docs/latest/prev/next/prev/doc_A.tdz
Status: DECOMPRESS
Author: Alice
===RECORD END===
===RECORD START===
Target: /home/user/docs/v2/prev/doc_C.tdz
Status: IGNORE
Author: Bob
===RECORD END===
===RECORD START===
Target: /home/user/docs/v1/next/prev/next/doc_B.tdz
Status: DECOMPRESS
Author: Charlie
===RECORD END===
EOF

    chmod -R 777 /home/user
