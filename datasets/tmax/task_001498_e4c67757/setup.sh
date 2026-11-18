#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    mkdir -p /home/user
    cd /home/user

    cat << 'EOF' > valid_json.json
[{"title": "API Reference", "content": "This is the API reference documentation."}]
EOF

    cat << 'EOF' > valid_csv.csv
title,content
User Guide,Welcome to the user guide.
EOF

    cat << 'EOF' > valid_xml.xml
<docs>
    <doc>
        <title>Release Notes</title>
        <content>Version 2.0 released.</content>
    </doc>
</docs>
EOF

    cat << 'EOF' > evil.txt
Malicious overwrite content
EOF

    cat << 'EOF' > create_tar.py
import tarfile

with tarfile.open('/home/user/incoming_docs.tar.gz', 'w:gz') as tar:
    # Safe files
    tar.add('valid_json.json', arcname='valid_json.json')
    tar.add('valid_csv.csv', arcname='valid_csv.csv')
    tar.add('valid_xml.xml', arcname='valid_xml.xml')

    # Malicious files (Tar Slip)
    tar.add('evil.txt', arcname='../evil_relative.txt')

    # Bypass tarfile's automatic absolute path stripping
    info = tar.gettarinfo('evil.txt')
    info.name = '/home/user/evil_absolute.txt'
    with open('evil.txt', 'rb') as f:
        tar.addfile(info, f)

    tar.add('evil.txt', arcname='subdir/../../evil_trick.txt')
EOF

    python3 create_tar.py
    rm valid_json.json valid_csv.csv valid_xml.xml evil.txt create_tar.py

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
