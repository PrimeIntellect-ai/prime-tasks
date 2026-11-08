#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip jq
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile
import io

base_dir = "/home/user/config_backups"
os.makedirs(base_dir, exist_ok=True)

# Data definition
logs = {
    "archive1": {
        "tar1": [
            "1680000000 api_gateway SET port 443",
            "1680000005 api_gateway SET host 127.0.0.1",
            "1680000010 db_server SET port 5432",
        ],
        "tar2": [
            "1680000020 api_gateway SET timeout 30",
            "1680000025 api_gateway DELETE host",
        ]
    },
    "archive2": {
        "tar3": [
            "1680000030 api_gateway SET host 0.0.0.0",
            "1680000040 api_gateway SET protocol https",
            "1680000050 db_server DELETE port",
        ],
        "tar4": [
            "1680000060 api_gateway SET banner Welcome to API Gateway!",
            "1680000065 api_gateway SET timeout 60",
            "1680000070 api_gateway DELETE protocol"
        ]
    }
}

for zip_name, tar_dict in logs.items():
    zip_path = os.path.join(base_dir, f"{zip_name}.zip")
    with zipfile.ZipFile(zip_path, 'w') as zf:
        for tar_name, lines in tar_dict.items():
            # Create a tar.gz in memory
            tar_stream = io.BytesIO()
            with tarfile.open(fileobj=tar_stream, mode='w:gz') as tf:
                wal_content = "\n".join(lines).encode('utf-8')
                tarinfo = tarfile.TarInfo(name=f"{tar_name}.wal")
                tarinfo.size = len(wal_content)
                tf.addfile(tarinfo, io.BytesIO(wal_content))

            tar_stream.seek(0)
            zf.writestr(f"{tar_name}.tar.gz", tar_stream.read())
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py

    chmod -R 777 /home/user
