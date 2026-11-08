#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr jq
    pip3 install pytest Pillow pytesseract

    mkdir -p /app/corpus/clean /app/corpus/evil

    # Generate the policy image and tarballs using Python
    python3 -c '
import os
import tarfile
import json
from PIL import Image, ImageDraw

# Create policy image
img = Image.new("RGB", (400, 200), color=(255, 255, 255))
d = ImageDraw.Draw(img)
text = "SECURITY MEMO\n\nEnsure all backups are sanitized.\nDENY_MOUNT: /media/usb_backup\n\nThank you."
d.text((10, 10), text, fill=(0, 0, 0))
img.save("/app/policy.png")

# Generate tarballs
os.chdir("/tmp")

# Clean 1
with open("app_config.json", "w") as f: json.dump({"mount_path": "/var/log"}, f)
with tarfile.open("/app/corpus/clean/clean1.tar", "w") as t: t.add("app_config.json")

# Clean 2
with open("app_config.json", "w") as f: json.dump({"mount_path": "/opt/app"}, f)
os.makedirs("assets", exist_ok=True)
with tarfile.open("/app/corpus/clean/clean2.tar", "w") as t:
    t.add("app_config.json")
    t.add("assets")

# Clean 3
with open("app_config.json", "w") as f: json.dump({"mount_path": "/media/usb"}, f)
with tarfile.open("/app/corpus/clean/clean3.tar", "w") as t: t.add("app_config.json")

# Evil 1
with tarfile.open("/app/corpus/evil/evil1_traversal.tar", "w") as t:
    ti = tarfile.TarInfo("../../../etc/shadow")
    ti.size = 0
    t.addfile(ti)

# Evil 2
with tarfile.open("/app/corpus/evil/evil2_absolute.tar", "w") as t:
    ti = tarfile.TarInfo("/tmp/pwned")
    ti.size = 0
    t.addfile(ti)

# Evil 3
with tarfile.open("/app/corpus/evil/evil3_symlink.tar", "w") as t:
    ti = tarfile.TarInfo("link")
    ti.type = tarfile.SYMTYPE
    ti.linkname = "/etc/passwd"
    t.addfile(ti)

# Evil 4
with open("app_config.json", "w") as f: json.dump({"mount_path": "/media/usb_backup"}, f)
with tarfile.open("/app/corpus/evil/evil4_policy.tar", "w") as t: t.add("app_config.json")

# Evil 5
with open("app_config.json", "w") as f: json.dump({"mount_path": "/media/usb_backup/database_dumps"}, f)
with tarfile.open("/app/corpus/evil/evil5_policy_sub.tar", "w") as t: t.add("app_config.json")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
