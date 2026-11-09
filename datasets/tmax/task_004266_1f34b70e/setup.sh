#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip gcc binutils zip unzip tar file jq
pip3 install pytest

# Create the dummy doc-extractor binary
mkdir -p /app
cat << 'EOF' > /tmp/extractor.c
#include <stdio.h>
int main() {
    printf("DOCXPT dummy\n");
    return 0;
}
EOF
gcc -o /app/doc-extractor /tmp/extractor.c
strip /app/doc-extractor
rm /tmp/extractor.c

# Create test data directories
mkdir -p /home/user/test_data/clean
mkdir -p /home/user/test_data/evil

# Python script to generate the .docbundle files
cat << 'EOF' > /tmp/gen_data.py
import os
import tarfile
import zipfile
import json

# Setup temp files
os.makedirs('/tmp/assets', exist_ok=True)

with open('/tmp/valid_meta.json', 'w') as f:
    json.dump({"doc_id": "doc-12345"}, f)

with open('/tmp/evil_meta1.json', 'w') as f:
    json.dump({"title": "No doc_id here"}, f)

with open('/tmp/evil_meta5.json', 'w') as f:
    f.write("{ invalid json")

with open('/tmp/valid.png', 'wb') as f:
    # Valid PNG magic
    f.write(b'\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82')

with open('/tmp/fake.png', 'wb') as f:
    # GIF magic header
    f.write(b'GIF89a\x01\x00\x01\x00\x80\x00\x00\xff\xff\xff\x00\x00\x00!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;')

with zipfile.ZipFile('/tmp/valid.zip', 'w') as z:
    z.writestr('hello.txt', 'world')

with zipfile.ZipFile('/tmp/nested.zip', 'w') as z:
    z.write('/tmp/valid.zip', 'inner.zip')

# Generate Clean bundles
for i in range(1, 6):
    with tarfile.open(f'/home/user/test_data/clean/clean{i}.docbundle', 'w') as tar:
        tar.add('/tmp/valid_meta.json', arcname='metadata.json')
        tar.add('/tmp/assets', arcname='assets')
        if i == 1:
            tar.add('/tmp/valid.zip', arcname='assets/valid.zip')
        elif i == 2:
            tar.add('/tmp/valid.png', arcname='assets/image.png')

# Generate Evil bundles
# evil1: missing doc_id
with tarfile.open('/home/user/test_data/evil/evil1.docbundle', 'w') as tar:
    tar.add('/tmp/evil_meta1.json', arcname='metadata.json')
    tar.add('/tmp/assets', arcname='assets')

# evil2: nested zip
with tarfile.open('/home/user/test_data/evil/evil2.docbundle', 'w') as tar:
    tar.add('/tmp/valid_meta.json', arcname='metadata.json')
    tar.add('/tmp/assets', arcname='assets')
    tar.add('/tmp/nested.zip', arcname='assets/nested.zip')

# evil3: fake png
with tarfile.open('/home/user/test_data/evil/evil3.docbundle', 'w') as tar:
    tar.add('/tmp/valid_meta.json', arcname='metadata.json')
    tar.add('/tmp/assets', arcname='assets')
    tar.add('/tmp/fake.png', arcname='assets/image.png')

# evil4: missing assets dir
with tarfile.open('/home/user/test_data/evil/evil4.docbundle', 'w') as tar:
    tar.add('/tmp/valid_meta.json', arcname='metadata.json')

# evil5: invalid json
with tarfile.open('/home/user/test_data/evil/evil5.docbundle', 'w') as tar:
    tar.add('/tmp/evil_meta5.json', arcname='metadata.json')
    tar.add('/tmp/assets', arcname='assets')

EOF
python3 /tmp/gen_data.py
rm -rf /tmp/gen_data.py /tmp/assets /tmp/*.json /tmp/*.png /tmp/*.zip

# Create user and set permissions
useradd -m -s /bin/bash user || true
chown -R user:user /home/user
chmod -R 777 /home/user
