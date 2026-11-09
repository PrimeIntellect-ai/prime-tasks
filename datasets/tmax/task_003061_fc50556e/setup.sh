#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go file gawk sed
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
os.makedirs("/home/user/project_dump", exist_ok=True)
os.makedirs("/home/user/assets/images", exist_ok=True)
os.makedirs("/home/user/assets/logs", exist_ok=True)

png_header = b"\x89\x50\x4E\x47\x0D\x0A\x1A\x0A\x00\x00\x00\x0D\x49\x48\x44\x52"

with open("/home/user/project_dump/config.txt", "wb") as f:
    f.write(png_header)
with open("/home/user/project_dump/unknown_blob", "wb") as f:
    f.write(png_header)

with open("/home/user/project_dump/readme.md", "w") as f:
    f.write("Just some random text.\n")
with open("/home/user/project_dump/image.png", "w") as f:
    f.write("Not a png file.\n")

with open("/home/user/project_dump/small.log", "w") as f:
    f.write("CRITICAL error from 192.168.1.1\n")

with open("/home/user/project_dump/app_server.log", "w") as f:
    f.write("INFO Starting server on 10.0.0.5\n")
    f.write("CRITICAL Database connection lost at 192.168.1.50!\n")
    f.write("DEBUG Loading config\n")
    f.write("CRITICAL User 192.168.1.100 failed login\n")
    f.write("INFO User authorized\n")
    f.write("CRITICAL Memory leak detected near 127.0.0.1\n")
    f.write("CRITICAL CPU temp high on 10.10.10.10\n")
    for i in range(1, 21):
        f.write(f"INFO general log entry {i}\n")
    for i in range(1, 31):
        f.write(f"CRITICAL subsystem failure from 172.16.0.{i}\n")
'

    chown -R user:user /home/user
    chmod -R 777 /home/user
