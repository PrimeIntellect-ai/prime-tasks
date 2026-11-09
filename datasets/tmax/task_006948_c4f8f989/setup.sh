#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user/logs
    mkdir -p /home/user/incoming

    cat << 'EOF' > /home/user/logs/upload_events.log
--- EVENT START ---
Timestamp: 2023-10-01 10:15:00
User ID: data_eng_01
Uploaded File: data.zip
Status: FAILED
--- EVENT END ---
--- EVENT START ---
Timestamp: 2023-10-01 11:22:30
User ID: intern_josh
Uploaded File: metadata.json
Status: SUCCESS
--- EVENT END ---
--- EVENT START ---
Timestamp: 2023-10-02 09:14:15
User ID: researcher_89
Uploaded File: data.zip
Status: SUCCESS
--- EVENT END ---
--- EVENT START ---
Timestamp: 2023-10-02 14:05:00
User ID: admin_sarah
Uploaded File: supplementary.zip
Status: SUCCESS
--- EVENT END ---
EOF

    cat << 'EOF' > /tmp/create_zip.py
import zipfile

with zipfile.ZipFile('/home/user/incoming/data.zip', 'w') as z:
    # Safe files
    z.writestr('dataset_info.txt', 'This is a clean dataset.')
    z.writestr('images/img1.png', '\x89PNG\r\n\x1a\n\x00\x00')
    z.writestr('images/img2.png', '\x89PNG\r\n\x1a\n\x00\x00')

    # Malicious files (Zip Slip)
    z.writestr('../../../home/user/.ssh/authorized_keys', 'ssh-rsa AAAAB3Nza... attacker@evil.com')
    z.writestr('images/../../etc/shadow', 'root:$6$xyz...:18000:0:99999:7:::')
    z.writestr('/absolute/path/malware.sh', '#!/bin/bash\nrm -rf /')
EOF
    python3 /tmp/create_zip.py
    rm /tmp/create_zip.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
