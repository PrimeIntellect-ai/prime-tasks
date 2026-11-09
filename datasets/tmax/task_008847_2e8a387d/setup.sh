#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/incoming
    mkdir -p /home/user/backup

    cat << 'EOF' > /home/user/config.json
{
  "incoming_dir": "/home/user/incoming",
  "backup_dir": "/home/user/backup",
  "state_file": "/home/user/state.json"
}
EOF

    echo "{}" > /home/user/state.json

    python3 -c "
import zipfile
with zipfile.ZipFile('/home/user/incoming/update.zip', 'w') as z:
    z.writestr('safe_doc.txt', 'This is a safe file.')
    z.writestr('src/app.py', 'print(\"Hello World\")')
    z.writestr('../../../evil.sh', 'rm -rf /')
    z.writestr('folder/../../another_evil.txt', 'bad')
"

    chmod -R 777 /home/user
