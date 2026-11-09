#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip build-essential tar gzip coreutils grep sed gawk
    pip3 install pytest

    mkdir -p /home/user/artifacts

    # Generate .art files
    python3 -c '
import struct

def make_art(filepath, version, name, size):
    with open(filepath, "wb") as f:
        f.write(b"ARTF")
        f.write(struct.pack("<I", version))
        name_bytes = name.encode("ascii")
        name_padded = name_bytes + b"\x00" * (32 - len(name_bytes))
        f.write(name_padded)
        f.write(struct.pack("<I", size))
        f.write(b"X" * size)

make_art("/home/user/artifacts/alpha.art", 1, "Alpha-Build", 100)
make_art("/home/user/artifacts/beta.art", 2, "Beta-Core", 250)
make_art("/home/user/artifacts/gamma.art", 1, "Gamma-Module", 50)
make_art("/home/user/artifacts/delta.art", 3, "Delta-Engine", 500)
'

    # Create deprecated.txt
    cat << 'EOF' > /home/user/deprecated.txt
Some general notes about the build system.
DEPRECATED: Beta-Core
We need to update the Gamma-Module soon.
DEPRECATED: Delta-Engine
EOF

    # Create a valid tarball, then corrupt it to test verification
    tar -czf /home/user/backup.tar.gz -C /home/user artifacts/
    # Corrupt the tarball slightly
    dd if=/dev/urandom of=/home/user/backup.tar.gz bs=1 count=10 seek=50 conv=notrunc

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
