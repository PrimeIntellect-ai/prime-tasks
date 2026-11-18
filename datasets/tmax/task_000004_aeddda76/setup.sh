#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/processed

    python3 -c '
import os
import tarfile
from io import BytesIO

incoming_dir = "/home/user/incoming"

# Archive 1: All safe files
arch1_path = os.path.join(incoming_dir, "archive1.tar.gz")
with tarfile.open(arch1_path, "w:gz") as tar:
    data1 = b"A" * 10
    ti1 = tarfile.TarInfo("file1.txt")
    ti1.size = len(data1)
    tar.addfile(ti1, BytesIO(data1))

    data2 = b"B" * 20
    ti2 = tarfile.TarInfo("dir/file2.txt")
    ti2.size = len(data2)
    tar.addfile(ti2, BytesIO(data2))

# Archive 2: Contains traversal (../)
arch2_path = os.path.join(incoming_dir, "archive2.tar.gz")
with tarfile.open(arch2_path, "w:gz") as tar:
    data1 = b"C" * 15
    ti1 = tarfile.TarInfo("safe.txt")
    ti1.size = len(data1)
    tar.addfile(ti1, BytesIO(data1))

    data2 = b"M" * 100
    ti2 = tarfile.TarInfo("../malicious.txt")
    ti2.size = len(data2)
    tar.addfile(ti2, BytesIO(data2))

# Archive 3: Contains absolute path (/)
arch3_path = os.path.join(incoming_dir, "archive3.tar.gz")
with tarfile.open(arch3_path, "w:gz") as tar:
    data1 = b"M" * 50
    ti1 = tarfile.TarInfo("/etc/passwd")
    ti1.size = len(data1)
    tar.addfile(ti1, BytesIO(data1))

    data2 = b"D" * 25
    ti2 = tarfile.TarInfo("log/safe.log")
    ti2.size = len(data2)
    tar.addfile(ti2, BytesIO(data2))
'

    chmod -R 777 /home/user
