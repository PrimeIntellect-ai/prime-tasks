#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/artifacts
    mkdir -p /home/user/extracted

    cat << 'EOF' > /home/user/curation_rules.ini
[Target]
directory = /home/user/artifacts
extension = .blob
min_size_bytes = 1000
EOF

    python3 -c "
import os

def make_file(path, prefix_len, suffix_len, config_str):
    with open(path, 'wb') as f:
        f.write(os.urandom(prefix_len))
        f.write(b'--CONFIG_START--')
        f.write(config_str.encode('utf-16le'))
        f.write(b'--CONFIG_END--')
        f.write(os.urandom(suffix_len))

make_file('/home/user/artifacts/serviceA.blob', 500, 500, 'loglevel=DEBUG\nenv=PROD')
make_file('/home/user/artifacts/serviceB.blob', 200, 1000, 'loglevel=INFO\nenv=STAGING')
make_file('/home/user/artifacts/serviceC.blob', 100, 300, 'loglevel=TRACE')
make_file('/home/user/artifacts/serviceD.bin', 500, 500, 'loglevel=WARN')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
