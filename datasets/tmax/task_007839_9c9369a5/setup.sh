#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/extracted
    cd /home/user

    python3 -c '
import zipfile
import os

with zipfile.ZipFile("repository.zip", "w") as z:
    z.writestr("valid1.hex", "48656c6c6f")
    z.writestr("valid2.txt", "World")
    z.writestr("subdir/valid3.hex", "476f")
    z.writestr("../evil.sh", "echo evil")
    z.writestr("/absolute/evil.txt", "echo absolute evil")
    z.writestr("subdir/../subdir2/valid4.txt", "NewFile")
'

    cat <<EOF > /home/user/previous_manifest.json
{
  "valid1.bin": "185f8db32271fe25f561a6fc938b2e264306ec304eda518007d1764826381969",
  "valid2.txt": "78ae647dc5a5f4689e4c24cb8c79c892b1b369b7365691d09e535fb6f1c713b1",
  "subdir/valid3.bin": "0000000000000000000000000000000000000000000000000000000000000000"
}
EOF

    chmod -R 777 /home/user
