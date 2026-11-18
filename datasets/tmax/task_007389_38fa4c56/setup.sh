#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    python3 -c '
import os
import zipfile
import hashlib

os.makedirs("/home/user/config_update", exist_ok=True)

service_a_content = b"port=8080\nenabled=true\n"
service_b_content = b"port=9090\nenabled=false\n"
service_b_old_content = b"port=9090\nenabled=true\n"
new_service_content = b"port=7070\n"
malicious_content = b"evil=true\n"

hash_a = hashlib.md5(service_a_content).hexdigest()
hash_b_old = hashlib.md5(service_b_old_content).hexdigest()

with open("/home/user/config_update/system.wal", "w") as f:
    f.write(f"ENTRY|1670000000|service_a.conf|{hash_a}\n")
    f.write(f"ENTRY|1670000100|service_b.conf|{hash_b_old}\n")

zip_path = "/home/user/config_update/patch.zip"
with zipfile.ZipFile(zip_path, "w") as zf:
    zf.writestr("service_a.conf", service_a_content)
    zf.writestr("service_b.conf", service_b_content)
    zf.writestr("new_service.conf", new_service_content)
    zf.writestr("../evil_traversal.conf", malicious_content)
    zf.writestr("/absolute/evil.conf", malicious_content)
'

    chmod -R 777 /home/user
