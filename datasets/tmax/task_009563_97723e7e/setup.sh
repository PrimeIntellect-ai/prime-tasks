#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip unzip tar
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /tmp/setup.py
import os
import zipfile
import tarfile

os.makedirs('/tmp/setup_docs', exist_ok=True)

# intro.txt (UTF-8)
with open('/tmp/setup_docs/intro.txt', 'w', encoding='utf-8') as f:
    f.write('This is the introduction.')

# notes_win.txt (Windows-1252)
with open('/tmp/setup_docs/notes_win.txt', 'wb') as f:
    f.write('Café and résumé.'.encode('windows-1252'))

# data.csv (ISO-8859-1)
with open('/tmp/setup_docs/data.csv', 'wb') as f:
    f.write('Item,Cost\nApple,1.00\nÜber,2.50'.encode('iso-8859-1'))

# nested_doc.txt (UTF-16)
with open('/tmp/setup_docs/nested_doc.txt', 'wb') as f:
    f.write('Nested secret document.'.encode('utf-16'))

# valid_nested.tar.gz
with tarfile.open('/tmp/setup_docs/valid_nested.tar.gz', 'w:gz') as tar:
    tar.add('/tmp/setup_docs/nested_doc.txt', arcname='nested_doc.txt')

# corrupt_nested.zip
with open('/tmp/setup_docs/corrupt_nested.zip', 'w') as f:
    f.write('This is definitely not a valid zip file format.')

# legacy_docs.zip
with zipfile.ZipFile('/home/user/legacy_docs.zip', 'w') as z:
    z.write('/tmp/setup_docs/intro.txt', 'intro.txt')
    z.write('/tmp/setup_docs/notes_win.txt', 'notes_win.txt')
    z.write('/tmp/setup_docs/data.csv', 'data.csv')
    z.write('/tmp/setup_docs/valid_nested.tar.gz', 'valid_nested.tar.gz')
    z.write('/tmp/setup_docs/corrupt_nested.zip', 'corrupt_nested.zip')
EOF

    python3 /tmp/setup.py
    rm -rf /tmp/setup.py /tmp/setup_docs

    chmod -R 777 /home/user
