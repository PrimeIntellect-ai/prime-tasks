#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /home/user/doc_archive/module1
    mkdir -p /home/user/doc_archive/module2/assets

    # XML
    cat << 'EOF' > /home/user/doc_archive/module1/intro.xml
<doc>
    <header>
        <title>Introduction to System</title>
    </header>
    <body>Welcome to the documentation.</body>
</doc>
EOF

    cat << 'EOF' > /home/user/doc_archive/module2/advanced.xml
<doc>
    <header>
        <title>Advanced Configuration</title>
    </header>
    <body>Details here.</body>
</doc>
EOF

    # JSON
    cat << 'EOF' > /home/user/doc_archive/module1/meta.json
{"doc_id": "m1", "author": "Jane Doe", "version": "1.0"}
EOF

    cat << 'EOF' > /home/user/doc_archive/module2/info.json
{"doc_id": "m2", "author": "John Smith", "tags": ["admin", "setup"]}
EOF

    # Binary Blobs written via Python to ensure correct byte values
    python3 -c '
with open("/home/user/doc_archive/module2/assets/graphic1.blob", "wb") as f:
    f.write(b"DOCBLOB1\xAA\xBB\xCC\xDD")
with open("/home/user/doc_archive/module2/assets/graphic2.blob", "wb") as f:
    f.write(b"DOCBLOB2\x11\x22\x33\x44")
with open("/home/user/doc_archive/module1/textdata.blob", "wb") as f:
    f.write(b"DOCBLOB1PAYLOAD_DATA_HERE")
'

    chown -R user:user /home/user/doc_archive
    chmod -R 777 /home/user
