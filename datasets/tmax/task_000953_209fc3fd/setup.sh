#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak
    pip3 install pytest

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil

    # Generate voicemail
    espeak -w /app/voicemail.wav "Hello, this is the previous admin. The new backup signature password is blue falcon seven."

    # Generate tar files
    python3 -c "
import tarfile
import os

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

with open('/tmp/dummy.txt', 'w') as f:
    f.write('dummy content')

def create_tar(path, members, signature):
    with tarfile.open(path, 'w') as tar:
        for name, type_, target in members:
            info = tarfile.TarInfo(name)
            if type_ == 'file':
                info.size = 13
                with open('/tmp/dummy.txt', 'rb') as f:
                    tar.addfile(info, f)
            elif type_ == 'symlink':
                info.type = tarfile.SYMTYPE
                info.linkname = target
                tar.addfile(info)
    with open(path, 'ab') as f:
        f.write(signature)

for i in range(1, 4):
    create_tar(f'/app/corpora/clean/clean{i}.tar', [('file1.txt', 'file', None)], b'BKP_bluefalconseven')

create_tar('/app/corpora/evil/evil1.tar', [('../../../etc/passwd', 'file', None)], b'BKP_bluefalconseven')
create_tar('/app/corpora/evil/evil2.tar', [('link1', 'symlink', '/root/secret')], b'BKP_bluefalconseven')
create_tar('/app/corpora/evil/evil3.tar', [('file1.txt', 'file', None)], b'BKP_wrongpassword')
create_tar('/app/corpora/evil/evil4.tar', [('/var/log/syslog', 'file', None)], b'BKP_bluefalconseven')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
