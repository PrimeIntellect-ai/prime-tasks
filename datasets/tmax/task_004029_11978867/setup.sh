#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip golang-go
    pip3 install pytest gTTS

    mkdir -p /app/corpus/clean /app/corpus/evil

    python3 -c '
import os
from gtts import gTTS

tts = gTTS("Attention. Any write ahead log containing transaction ID six six six is malicious and must be rejected.")
tts.save("/app/research_note.wav")

def encode_rle(text):
    res = bytearray()
    for char in text:
        res.append(1)
        res.append(ord(char))
    return res

clean_text = "TXN:100 DATA:ok\nTXN:101 DATA:ok\n"
with open("/app/corpus/clean/file1.wal.rle", "wb") as f:
    f.write(encode_rle(clean_text))

evil_text = "TXN:100 DATA:ok\nTXN:666 DATA:malicious\n"
with open("/app/corpus/evil/bad1.wal.rle", "wb") as f:
    f.write(encode_rle(evil_text))
'

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
