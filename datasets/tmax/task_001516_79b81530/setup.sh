#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg golang
    pip3 install pytest

    mkdir -p /app/legacy_logs/systemA /app/legacy_logs/systemB /app/archiver /app/archive_stage
    cd /app

    python3 -c '
import os
with open("/app/legacy_logs/systemA/log1.txt", "w", encoding="iso-8859-1") as f:
    f.write("INFO System boot\n")
    f.write("CRITICAL_BACKUP_FAILURE disk 0x1A\n")
    f.write("WARN cpu high\n")

with open("/app/legacy_logs/systemB/log2.txt", "w", encoding="utf-16le") as f:
    f.write("CRITICAL_BACKUP_FAILURE network drop\n")
    f.write("INFO sync complete\n")
'

    ffmpeg -y -f lavfi -i color=c=black:s=320x240:r=10:d=10 \
      -vf "drawbox=x=0:y=0:w=320:h=240:color=white@1.0:t=fill:enable='between(t,2,4.49)'" \
      -c:v libx264 -pix_fmt yuv420p /app/audit.mp4

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
