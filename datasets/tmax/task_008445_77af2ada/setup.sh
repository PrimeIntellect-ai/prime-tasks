#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip g++
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/config_updates

    python3 -c '
import os
with open("/home/user/config_updates/update_01.txt", "w", encoding="utf-8") as f:
    f.write("title=Hello World\nmsg=Good morning\n")

with open("/home/user/config_updates/update_02.txt", "w", encoding="utf-8") as f:
    f.write("title=Hola\nmsg=Buenos días\n")

with open("/home/user/config_updates/update_03.txt", "wb") as f:
    f.write(b"title=Bad\nmsg=Corrupt\xFFData\n")

with open("/home/user/config_updates/update_04.txt", "w", encoding="utf-8") as f:
    f.write("title=你好\nmsg=早上好\n")

with open("/home/user/config_updates/update_05.txt", "w", encoding="utf-8") as f:
    f.write("title=مرحبا\n")
'

    chmod -R 777 /home/user
