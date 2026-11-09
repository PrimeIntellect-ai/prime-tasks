#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /app

    python3 -c '
import zipfile
import os
import random

os.makedirs("/app/corpora/clean", exist_ok=True)
os.makedirs("/app/corpora/evil", exist_ok=True)
os.makedirs("/app/recent_uploads", exist_ok=True)

# Generate clean zips
for i in range(10):
    path = f"/app/corpora/clean/clean_{i}.zip"
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr(f"docs/readme_{i}.txt", "clean content")

# Generate evil zips
evil_paths = [
    "../../etc/passwd",
    "../var/log/syslog",
    "C:\\Windows\\System32\\cmd.exe",
    "/var/www/html/shell.php",
    "..././etc/shadow",
    "..\\..\\boot.ini",
    "docs/../../etc/passwd",
    "/etc/hosts",
    "../home/user/.bashrc",
    "..//..//etc//passwd"
]
for i in range(10):
    path = f"/app/corpora/evil/evil_{i}.zip"
    with zipfile.ZipFile(path, "w") as zf:
        zf.writestr(evil_paths[i], "evil content")

# Generate invalid zips
for i in range(5):
    path = f"/app/recent_uploads/invalid_{i}.zip"
    with open(path, "wb") as f:
        f.write(os.urandom(100))

uploads = []
def add_upload(user, ftype, idx):
    filename = f"{user}_{ftype}_{idx}.zip"
    uploads.append((user, filename))
    dest = f"/app/recent_uploads/{filename}"
    if ftype == "clean":
        os.system(f"cp /app/corpora/clean/clean_{idx}.zip {dest}")
    elif ftype == "evil":
        os.system(f"cp /app/corpora/evil/evil_{idx}.zip {dest}")
    elif ftype == "invalid":
        os.system(f"cp /app/recent_uploads/invalid_{idx}.zip {dest}")

add_upload("eve_hacker", "evil", 0)
add_upload("eve_hacker", "evil", 1)
add_upload("eve_hacker", "evil", 2)
add_upload("eve_hacker", "evil", 3)
add_upload("eve_hacker", "evil", 4)
add_upload("eve_hacker", "clean", 0)

add_upload("alice", "evil", 5)
add_upload("alice", "evil", 6)
add_upload("alice", "clean", 1)
add_upload("alice", "clean", 2)
add_upload("alice", "clean", 3)

add_upload("bob", "evil", 7)
add_upload("bob", "clean", 4)
add_upload("bob", "clean", 5)
for i in range(5):
    add_upload("bob", "invalid", i)

random.shuffle(uploads)

with open("/app/upload_service.log", "w") as f:
    for u, fn in uploads:
        f.write("[START UPLOAD]\n")
        f.write("Timestamp: 2023-10-01T12:00:00Z\n")
        f.write(f"User: {u}\n")
        f.write(f"Archive: {fn}\n")
        f.write("[END UPLOAD]\n")

os.makedirs("/app/py-archive-validator-1.0.0/validator", exist_ok=True)
with open("/app/py-archive-validator-1.0.0/validator/__init__.py", "w") as f:
    pass
with open("/app/py-archive-validator-1.0.0/validator/core.py", "w") as f:
    f.write("""def is_safe_path(filename):
    if "../" in filename:
        return False
    if filename.startswith("/"):
        return False
    return True
""")
with open("/app/py-archive-validator-1.0.0/setup.py", "w") as f:
    f.write("""from setuptools import setup, find_packages
setup(name="py-archive-validator", version="1.0.0", packages=find_packages())
""")
    '

    pip3 install -e /app/py-archive-validator-1.0.0/

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
