#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cargo rustc build-essential coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming/chunks
    mkdir -p /home/user/workspace
    mkdir -p /tmp/malicious_tar_build

    cd /tmp/malicious_tar_build
    cat << 'EOF' > build_tar.py
import tarfile
import io

with tarfile.open("backup.tar", "w") as tar:
    # 1. Valid file
    valid_info = tarfile.TarInfo(name="config/server.yaml")
    valid_data = b"host: localhost\nport: 8080\n"
    valid_info.size = len(valid_data)
    tar.addfile(valid_info, io.BytesIO(valid_data))

    # 2. Path traversal (Tar slip)
    slip_info = tarfile.TarInfo(name="../escaped_secret.txt")
    slip_data = b"You are compromised!\n"
    slip_info.size = len(slip_data)
    tar.addfile(slip_info, io.BytesIO(slip_data))

    # 3. Absolute path
    abs_info = tarfile.TarInfo(name="/etc/fake_passwd")
    abs_data = b"root:x:0:0:root:/root:/bin/bash\n"
    abs_info.size = len(abs_data)
    tar.addfile(abs_info, io.BytesIO(abs_data))

    # 4. Malicious symlink
    sym_info = tarfile.TarInfo(name="config/link_to_root")
    sym_info.type = tarfile.SYMTYPE
    sym_info.linkname = "/etc"
    tar.addfile(sym_info)

    # 5. Valid symlink
    vsym_info = tarfile.TarInfo(name="config/link_to_server")
    vsym_info.type = tarfile.SYMTYPE
    vsym_info.linkname = "server.yaml"
    tar.addfile(vsym_info)
EOF

    python3 build_tar.py
    gzip backup.tar

    # Split into chunks
    split -b 150 backup.tar.gz /home/user/incoming/chunks/backup.tar.gz.part-

    # Generate checksums
    cd /home/user/incoming/chunks
    sha256sum backup.tar.gz.part-* > /home/user/incoming/checksums.sha256

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incoming /home/user/workspace
    chmod -R 777 /home/user
