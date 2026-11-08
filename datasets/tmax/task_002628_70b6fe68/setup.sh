#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest Pillow

    # Generate the image and corpus files
    python3 -c '
import os
import hashlib
from PIL import Image, ImageDraw

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

img = Image.new("RGB", (400, 100), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "POLICY_SALT: s3cr3t_S@lt_99", fill=(0, 0, 0))
d.text((10, 50), "BANNED_CWE: CWE-78", fill=(0, 0, 0))
img.save("/app/policy.png")

salt = b"s3cr3t_S@lt_99"

def write_file(path, content, bad_sig=False):
    sig = hashlib.sha256(content.encode("utf-8") + salt).hexdigest()
    if bad_sig:
        sig = "0000000000000000000000000000000000000000000000000000000000000000"
    with open(path, "w") as f:
        f.write(f"# SIGNATURE: {sig}\n")
        f.write(content)

write_file("/app/corpus/clean/clean1.py", "import subprocess\nsubprocess.run([\"ls\", \"-l\"])\n")
write_file("/app/corpus/clean/clean2.py", "print(\"hello\")\n")

write_file("/app/corpus/evil/evil1.py", "print(\"hello\")\n", bad_sig=True)
write_file("/app/corpus/evil/evil2.py", "import os\nos.system(\"ls -l\")\n")
write_file("/app/corpus/evil/evil3.py", "import subprocess\nsubprocess.Popen(\"ls -l\", shell=True)\n")
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
