#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg
    pip3 install pytest gTTS

    mkdir -p /app/corpora/clean
    mkdir -p /app/corpora/evil
    mkdir -p /app/corpora/eval_mixed

    cat << 'EOF' > /tmp/setup.py
import os
import struct
import shutil
import subprocess
from gtts import gTTS

# Generate voicemail
text = "Hey, it's Alice. I tracked down the service crash. The memory leak is caused by malformed WAV files containing a custom chunk named 'acid'. Our parser incorrectly reads the 4-byte size field of this chunk as a signed 32-bit little-endian integer. If attackers set it to a negative value, the buffer allocation overflows, fails to skip the chunk, and leaks memory. To fix this in the ingest pipeline, build a filter that rejects any WAV file containing an 'acid' chunk where the parsed signed integer size is less than zero. Accept all other files."
tts = gTTS(text)
tts.save('/tmp/voicemail.mp3')
subprocess.run(['ffmpeg', '-y', '-i', '/tmp/voicemail.mp3', '/app/voicemail.wav'], check=True)

# Generate corpora
def make_wav(path, chunk_id=None, chunk_size=None):
    with open(path, 'wb') as f:
        f.write(b'RIFF')
        f.write(struct.pack('<I', 36))
        f.write(b'WAVE')
        f.write(b'fmt ')
        f.write(struct.pack('<I', 16))
        f.write(b'\x01\x00\x01\x00\x44\xac\x00\x00\x88\x58\x01\x00\x02\x00\x10\x00')
        f.write(b'data')
        f.write(struct.pack('<I', 0))
        if chunk_id:
            f.write(chunk_id)
            if chunk_size is not None:
                f.write(struct.pack('<i', chunk_size))
            else:
                f.write(struct.pack('<I', 0))

make_wav('/app/corpora/clean/clean1.wav')
make_wav('/app/corpora/clean/clean2.wav', b'acid', 100)
make_wav('/app/corpora/evil/evil1.wav', b'acid', -1)
make_wav('/app/corpora/evil/evil2.wav', b'acid', -50)

shutil.copy('/app/corpora/clean/clean1.wav', '/app/corpora/eval_mixed/clean1.wav')
shutil.copy('/app/corpora/clean/clean2.wav', '/app/corpora/eval_mixed/clean2.wav')
shutil.copy('/app/corpora/evil/evil1.wav', '/app/corpora/eval_mixed/evil1.wav')
shutil.copy('/app/corpora/evil/evil2.wav', '/app/corpora/eval_mixed/evil2.wav')
EOF

    python3 /tmp/setup.py
    rm /tmp/setup.py /tmp/voicemail.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
