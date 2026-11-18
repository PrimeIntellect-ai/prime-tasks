#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip
pip3 install pytest

useradd -m -s /bin/bash user || true

cat << 'EOF' > /tmp/setup.py
import tarfile
import os

os.makedirs("/home/user", exist_ok=True)
tar_path = "/home/user/updates.tar"

with tarfile.open(tar_path, "w") as tar:
    # 1. Safe regular file
    safe_file = tarfile.TarInfo("safe_config.ini")
    safe_file.size = 12
    with open("/tmp/dummy1", "wb") as f: f.write(b"safe content")
    with open("/tmp/dummy1", "rb") as f: tar.addfile(safe_file, f)

    # 2. Safe directory
    safe_dir = tarfile.TarInfo("safe_dir")
    safe_dir.type = tarfile.DIRTYPE
    tar.addfile(safe_dir)

    # 3. Zip slip file (absolute path)
    slip_abs = tarfile.TarInfo("/home/user/evil1.txt")
    slip_abs.size = 4
    with open("/tmp/dummy2", "wb") as f: f.write(b"evil")
    with open("/tmp/dummy2", "rb") as f: tar.addfile(slip_abs, f)

    # 4. Zip slip file (relative path traversal)
    slip_rel = tarfile.TarInfo("safe_dir/../../evil2.txt")
    slip_rel.size = 4
    with open("/tmp/dummy3", "wb") as f: f.write(b"evil")
    with open("/tmp/dummy3", "rb") as f: tar.addfile(slip_rel, f)

    # 5. Safe symlink
    safe_sym = tarfile.TarInfo("safe_symlink")
    safe_sym.type = tarfile.SYMTYPE
    safe_sym.linkname = "safe_config.ini"
    tar.addfile(safe_sym)

    # 6. Unsafe symlink (target outside)
    unsafe_sym = tarfile.TarInfo("unsafe_symlink")
    unsafe_sym.type = tarfile.SYMTYPE
    unsafe_sym.linkname = "../outside.txt"
    tar.addfile(unsafe_sym)

    # 7. Unsafe hardlink
    unsafe_hard = tarfile.TarInfo("unsafe_hardlink")
    unsafe_hard.type = tarfile.LNKTYPE
    unsafe_hard.linkname = "/etc/passwd"
    tar.addfile(unsafe_hard)
EOF

python3 /tmp/setup.py

chmod -R 777 /home/user
