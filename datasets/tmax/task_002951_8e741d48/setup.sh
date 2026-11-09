#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip unzip
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate initial state using Python
    cat << 'EOF' > /tmp/setup_zips.py
import os
import zipfile

os.makedirs('/home/user/docs_incoming', exist_ok=True)

# Safe doc 1
with zipfile.ZipFile('/home/user/docs_incoming/doc_alpha.zip', 'w') as z:
    z.writestr('intro.md', '# Introduction\nSafe file.')
    z.writestr('guide/setup.md', '# Setup\nSafe setup.')

# Malicious doc 1 (relative path traversal)
with zipfile.ZipFile('/home/user/docs_incoming/doc_beta_malicious.zip', 'w') as z:
    z.writestr('normal.md', 'Normal file')

    # Manually adding a zipinfo with a malicious path
    info = zipfile.ZipInfo('../overwrite_sys.txt')
    z.writestr(info, 'Malicious content')

# Safe doc 2
with zipfile.ZipFile('/home/user/docs_incoming/doc_gamma.zip', 'w') as z:
    z.writestr('api_reference.md', '# API\nSafe API doc.')

# Malicious doc 2 (absolute path)
with zipfile.ZipFile('/home/user/docs_incoming/doc_delta_bad.zip', 'w') as z:
    info = zipfile.ZipInfo('/etc/shadow_fake')
    z.writestr(info, 'Fake shadow')
EOF

    python3 /tmp/setup_zips.py
    rm /tmp/setup_zips.py

    chmod -R 777 /home/user
