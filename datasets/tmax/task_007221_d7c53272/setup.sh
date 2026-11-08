#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/images

    cat << 'EOF' > /home/user/backup.ini
[Backup]
source_dir = /home/user/images
archive_path = /home/user/incremental_backup.tar.gz
state_file = /home/user/backup_state.json
EOF

    python3 -c '
import os, json

# Create files with exact bytes
files = {
    "old.png": b"\x89PNG\r\n\x1a\nrestofdata1",
    "updated.png": b"\x89PNG\r\n\x1a\nrestofdata2",
    "new.png": b"\x89PNG\r\n\x1a\nrestofdata3",
    "fake.png": b"NOTAPNG\r\n\x1a\nrestofdata"
}

for name, content in files.items():
    with open(f"/home/user/images/{name}", "wb") as f:
        f.write(content)

# Set state file
state = {
    "old.png": os.path.getmtime("/home/user/images/old.png"),
    "updated.png": os.path.getmtime("/home/user/images/old.png") - 1000.0, # Make it older so it gets backed up
    "deleted.png": 1672574400.0
}
with open("/home/user/backup_state.json", "w") as f:
    json.dump(state, f)
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
