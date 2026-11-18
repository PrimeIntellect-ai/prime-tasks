#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import tarfile

base_dir = "/home/user"
os.makedirs(base_dir, exist_ok=True)
tar_path = os.path.join(base_dir, "project_files.tar")

os.makedirs("/tmp/tar_setup/docs", exist_ok=True)
os.makedirs("/tmp/tar_setup/logs", exist_ok=True)
os.makedirs("/tmp/tar_setup/src", exist_ok=True)

with open("/tmp/tar_setup/docs/readme.txt", "w") as f:
    f.write("Project documentation.\n")

with open("/tmp/tar_setup/docs/info.txt", "w") as f:
    f.write("More info.\n")

with open("/tmp/tar_setup/logs/system.log", "w") as f:
    f.write("INFO: Starting up\nERROR: memory leak detected\nWARN: High CPU\n")

with open("/tmp/tar_setup/logs/app.log", "w") as f:
    f.write("DEBUG: init\nERROR: null pointer exception\nINFO: exiting\n")

with open("/tmp/tar_setup/src/main.c", "w") as f:
    f.write("int main() { return 0; }\n")

with open("/tmp/tar_setup/shadow.bak", "w") as f:
    f.write("root:*:18333:0:99999:7:::\n")

with open("/tmp/tar_setup/backdoor.php", "w") as f:
    f.write("<?php system($_GET['cmd']); ?>\n")

with tarfile.open(tar_path, "w") as tar:
    # Safe paths
    tar.add("/tmp/tar_setup/docs/readme.txt", arcname="docs/readme.txt")
    tar.add("/tmp/tar_setup/logs/system.log", arcname="logs/system.log")
    tar.add("/tmp/tar_setup/src/main.c", arcname="src/main.c")

    # Paths with traversal that need exact name preservation
    def add_exact(src, name):
        info = tar.gettarinfo(src)
        info.name = name
        with open(src, "rb") as f:
            tar.addfile(info, f)

    add_exact("/tmp/tar_setup/docs/info.txt", "docs/../docs/info.txt")
    add_exact("/tmp/tar_setup/logs/app.log", "logs/../logs/app.log")
    add_exact("/tmp/tar_setup/shadow.bak", "../etc/shadow.bak")
    add_exact("/tmp/tar_setup/backdoor.php", "/var/www/html/backdoor.php")
    add_exact("/tmp/tar_setup/backdoor.php", "docs/../../var/tmp/bad.sh")

os.system("rm -rf /tmp/tar_setup")
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
