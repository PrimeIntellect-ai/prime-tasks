#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os

os.makedirs("/home/user/configs", exist_ok=True)

files = [
    {
        "name": "backup_2023-01-05.ini",
        "encoding": "utf-8",
        "content": "[General]\nver=1.0\n[Security]\nkey_A=1\nkey_B=2\nkey_C=3\n[Database]\nhost=localhost\n"
    },
    {
        "name": "backup_2023-01-20.ini",
        "encoding": "utf-16",
        "content": "[Security]\nkey_B=val\nkey_C=val\nkey_D=val\n"
    },
    {
        "name": "backup_2023-02-10.ini",
        "encoding": "utf-8",
        "content": "[Network]\nport=80\n[Security]\nkey_C=x\nkey_D=y\nkey_E=z\n"
    },
    {
        "name": "backup_2023-03-01.ini",
        "encoding": "utf-16",
        "content": "[General]\nver=1.1\n[Security]\nkey_E=1\nkey_F=2\n"
    },
    {
        "name": "backup_2023-03-15.ini",
        "encoding": "utf-8",
        "content": "[Security]\nkey_E=1\nkey_F=2\nkey_G=3\n[Other]\nfoo=bar\n"
    }
]

for f in files:
    path = os.path.join("/home/user/configs", f["name"])
    with open(path, "w", encoding=f["encoding"]) as out:
        out.write(f["content"])
'

    chmod -R 777 /home/user
