#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    # Generate the wiki.wal file
    python3 -c '
import struct
import os

def rle_encode(text):
    if not text:
        return b""
    encoded = bytearray()
    i = 0
    while i < len(text):
        count = 1
        while i + 1 < len(text) and text[i] == text[i+1] and count < 255:
            count += 1
            i += 1
        encoded.append(count)
        encoded.append(ord(text[i]))
        i += 1
    return bytes(encoded)

def create_wal_record(doc_id, text):
    magic = b"DOC5"
    compressed = rle_encode(text)
    length = len(compressed)
    return magic + struct.pack("<II", doc_id, length) + compressed

records = [
    (101, "Initial API Draft"),
    (102, "User Guide V1"),
    (101, "API Documentation Final"),
    (103, "Internal Developer Notes"),
    (102, "User Guide V2 Final"),
    (104, "Deprecated System Architecture"),
    (104, "Archived System Architecture"),
]

wal_data = bytearray()
for doc_id, text in records:
    wal_data.extend(create_wal_record(doc_id, text))

os.makedirs("/home/user", exist_ok=True)
with open("/home/user/wiki.wal", "wb") as f:
    f.write(wal_data)
'

    chmod -R 777 /home/user
