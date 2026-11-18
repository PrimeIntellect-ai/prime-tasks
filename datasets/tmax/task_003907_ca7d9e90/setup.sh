#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app
    espeak -w /app/voicemail.wav "Hi, it's the boss. We need to clear out the storage. Delete any archive where the total uncompressed size of its contents exceeds ten megabytes, or if the archive contains any files ending with the dot exe extension. Accept everything else."

    python3 -c "
import tarfile
import os

os.makedirs('/app/corpora/clean', exist_ok=True)
os.makedirs('/app/corpora/evil', exist_ok=True)

with open('small.txt', 'wb') as f:
    f.write(b'a' * 1024)

with open('large.txt', 'wb') as f:
    f.write(b'a' * (11 * 1024 * 1024))

with open('malware.exe', 'wb') as f:
    f.write(b'bad')

with tarfile.open('/app/corpora/clean/clean1.tar.gz', 'w:gz') as tar:
    tar.add('small.txt')

with tarfile.open('/app/corpora/clean/clean2.tar.gz', 'w:gz') as tar:
    tar.add('small.txt', arcname='another.txt')

with tarfile.open('/app/corpora/evil/evil1.tar.gz', 'w:gz') as tar:
    tar.add('large.txt')

with tarfile.open('/app/corpora/evil/evil2.tar.gz', 'w:gz') as tar:
    tar.add('malware.exe')

os.remove('small.txt')
os.remove('large.txt')
os.remove('malware.exe')
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
