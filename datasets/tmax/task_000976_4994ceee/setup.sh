#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tesseract-ocr
    pip3 install pytest Pillow

    python3 -c '
import os
import json
import hashlib
from PIL import Image, ImageDraw

os.makedirs("/app/corpus/clean", exist_ok=True)
os.makedirs("/app/corpus/evil", exist_ok=True)

img = Image.new("RGB", (200, 50), color=(255, 255, 255))
d = ImageDraw.Draw(img)
d.text((10, 10), "SALT: K8sL10n2024", fill=(0, 0, 0))
img.save("/app/l10n_secret.png")

salt = "K8sL10n2024"

def make_hash(msgid, msgstr):
    return hashlib.md5((msgid + msgstr + salt).encode()).hexdigest()

for i in range(5):
    data = []
    for j in range(15):
        msgid = f"msg.clean.{i}.{j}"
        msgstr = f"Trans {i} {j}"
        data.append({"msgid": msgid, "msgstr": msgstr, "hash": make_hash(msgid, msgstr)})
    with open(f"/app/corpus/clean/file_{i}.json", "w") as f:
        json.dump(data, f)

data1 = []
for j in range(5):
    msgid = f"msg.evil.1.{j}"
    msgstr = f"Trans 1 {j}"
    data1.append({"msgid": msgid, "msgstr": msgstr, "hash": make_hash(msgid, msgstr)})
data1.append(data1[0].copy())
with open("/app/corpus/evil/evil_1.json", "w") as f: json.dump(data1, f)

data2 = [{"msgid": "a", "msgstr": "b", "hash": make_hash("a", "b")[:-1] + ("0" if make_hash("a", "b")[-1] != "0" else "1")}]
with open("/app/corpus/evil/evil_2.json", "w") as f: json.dump(data2, f)

data3 = [{"msgid": "a", "msgstr": "b", "hash": hashlib.md5(b"abWRONGSALT").hexdigest()}]
with open("/app/corpus/evil/evil_3.json", "w") as f: json.dump(data3, f)

data4 = [{"msgid": "a", "msgstr": "b", "hash": make_hash("a", "b")}, {"msgid": "a", "msgstr": "c", "hash": make_hash("a", "c")}]
with open("/app/corpus/evil/evil_4.json", "w") as f: json.dump(data4, f)

data5 = [{"msgid": "a", "msgstr": "b", "hash": "invalid"}]
with open("/app/corpus/evil/evil_5.json", "w") as f: json.dump(data5, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
