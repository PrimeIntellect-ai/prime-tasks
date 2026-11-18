#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak tar
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    espeak -w /app/intercepted_comms.wav "The compromised project code is VANGUARD-7. I repeat, VANGUARD-7."

    cat << 'EOF' > /tmp/setup_corpora.py
import tarfile
import hashlib
import os

def make_clean():
    os.makedirs('/tmp/clean_tmp', exist_ok=True)
    with open('/tmp/clean_tmp/payload.bin', 'wb') as f:
        f.write(b'clean data')
    with open('/tmp/clean_tmp/metadata.txt', 'wb') as f:
        f.write('PROJECT-APOLLO'.encode('shift_jis'))

    sha = hashlib.sha256(b'clean data').hexdigest()
    with open('/tmp/clean_tmp/manifest.sha256', 'w') as f:
        f.write(f'{sha}  payload.bin\n')

    with tarfile.open('/app/corpora/clean/clean_1.tar.gz', 'w:gz') as tar:
        tar.add('/tmp/clean_tmp/payload.bin', arcname='payload.bin')
        tar.add('/tmp/clean_tmp/metadata.txt', arcname='metadata.txt')
        tar.add('/tmp/clean_tmp/manifest.sha256', arcname='manifest.sha256')

def make_evil_1():
    with tarfile.open('/app/corpora/evil/evil_1.tar.gz', 'w:gz') as tar:
        ti = tarfile.TarInfo('../etc/passwd')
        ti.size = 0
        tar.addfile(ti, open(os.devnull, 'rb'))

def make_evil_2():
    os.makedirs('/tmp/evil2_tmp', exist_ok=True)
    with open('/tmp/evil2_tmp/payload.bin', 'wb') as f:
        f.write(b'evil data')
    with open('/tmp/evil2_tmp/manifest.sha256', 'w') as f:
        f.write('0000000000000000000000000000000000000000000000000000000000000000  payload.bin\n')
    with tarfile.open('/app/corpora/evil/evil_2.tar.gz', 'w:gz') as tar:
        tar.add('/tmp/evil2_tmp/payload.bin', arcname='payload.bin')
        tar.add('/tmp/evil2_tmp/manifest.sha256', arcname='manifest.sha256')

def make_evil_3():
    os.makedirs('/tmp/evil3_tmp', exist_ok=True)
    with open('/tmp/evil3_tmp/payload.bin', 'wb') as f:
        f.write(b'data')
    with open('/tmp/evil3_tmp/metadata.txt', 'wb') as f:
        f.write('VANGUARD-7'.encode('shift_jis'))
    sha = hashlib.sha256(b'data').hexdigest()
    with open('/tmp/evil3_tmp/manifest.sha256', 'w') as f:
        f.write(f'{sha}  payload.bin\n')
    with tarfile.open('/app/corpora/evil/evil_3.tar.gz', 'w:gz') as tar:
        tar.add('/tmp/evil3_tmp/payload.bin', arcname='payload.bin')
        tar.add('/tmp/evil3_tmp/metadata.txt', arcname='metadata.txt')
        tar.add('/tmp/evil3_tmp/manifest.sha256', arcname='manifest.sha256')

def make_evil_4():
    with tarfile.open('/app/corpora/evil/evil_4.tar.gz', 'w:gz') as tar:
        ti = tarfile.TarInfo('/var/tmp/malicious.sh')
        ti.size = 0
        tar.addfile(ti, open(os.devnull, 'rb'))

make_clean()
make_evil_1()
make_evil_2()
make_evil_3()
make_evil_4()
EOF

    python3 /tmp/setup_corpora.py
    rm -rf /tmp/setup_corpora.py /tmp/clean_tmp /tmp/evil2_tmp /tmp/evil3_tmp

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
