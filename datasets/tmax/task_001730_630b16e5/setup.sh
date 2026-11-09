#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/setup.py
import os
import tarfile
import zipfile
import gzip
import shutil

os.makedirs("/home/user/setup_temp", exist_ok=True)
os.chdir("/home/user/setup_temp")

# Create base markdown files
with open("alpha.md", "w") as f:
    f.write("# Alpha\nThis is the alpha doc.")
with open("beta.md", "w") as f:
    f.write("# Beta\nBeta documentation.")
with open("gamma.md", "w") as f:
    f.write("# Gamma\nGamma notes.")
with open("delta.md", "w") as f:
    f.write("# Delta\nDelta notes.")

# Create innermost GZIP tarball (misnamed as .dat)
with tarfile.open("inner.tar.gz", "w:gz") as tar:
    tar.add("gamma.md")
    tar.add("delta.md")
os.rename("inner.tar.gz", "team_notes.dat")

# Create middle ZIP archive (misnamed as .bin)
with zipfile.ZipFile("middle.zip", "w") as z:
    z.write("beta.md")
    z.write("team_notes.dat")
os.rename("middle.zip", "project.bin")

# Create outermost TAR archive
os.chdir("/home/user")
with tarfile.open("docs_archive.tar", "w") as tar:
    tar.add("setup_temp/alpha.md", arcname="alpha.md")
    tar.add("setup_temp/project.bin", arcname="project.bin")

shutil.rmtree("/home/user/setup_temp")
EOF

    python3 /home/user/setup.py
    rm /home/user/setup.py

    chmod -R 777 /home/user
