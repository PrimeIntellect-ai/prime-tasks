#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get install -y python3 python3-pip ffmpeg gcc zlib1g-dev
pip3 install pytest

mkdir -p /app/corpus/clean /app/corpus/evil

# Generate the video
ffmpeg -f lavfi -i testsrc=duration=5:rate=30 -g 12 -c:v libx264 /app/config_session.mp4

# Generate test corpus
python3 -c "
import gzip
import struct

def write_file(path, magic, version, encoding, payload):
    with gzip.open(path, 'wb') as f:
        f.write(magic)
        f.write(struct.pack('<H', version))
        f.write(struct.pack('<H', encoding))
        f.write(payload)

write_file('/app/corpus/clean/clean1.gz', b'CFG!', 13, 0, b'SET_VAR=1')
write_file('/app/corpus/clean/clean2.gz', b'CFG!', 13, 1, 'UPDATE'.encode('utf-16le'))
write_file('/app/corpus/evil/evil1.gz', b'BAD!', 13, 0, b'OK')
write_file('/app/corpus/evil/evil2.gz', b'CFG!', 99, 0, b'OK')
write_file('/app/corpus/evil/evil3.gz', b'CFG!', 13, 0, b'DROP_TABLE users;')
write_file('/app/corpus/evil/evil4.gz', b'CFG!', 13, 1, 'DROP_TABLE'.encode('utf-16le'))
"

useradd -m -s /bin/bash user || true
chmod -R 777 /home/user
chmod -R 777 /app
