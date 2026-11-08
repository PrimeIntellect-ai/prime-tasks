#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import struct, gzip, os

os.makedirs('/home/user/artifacts', exist_ok=True)

def make_dat(name, id_val, ts):
    # Pack: 4s (magic), I (uint32 LE), Q (uint64 LE)
    header = struct.pack('<4sIQ', b'BLOB', id_val, ts)
    payload = os.urandom(64)
    data = header + payload

    filepath = f'/home/user/artifacts/{name}'
    with gzip.open(filepath, 'wb') as f:
        f.write(data)

make_dat('alpha.dat', 101, 1672531200)
make_dat('beta.dat', 102, 1672617600)
make_dat('gamma.dat', 103, 1672704000)
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
