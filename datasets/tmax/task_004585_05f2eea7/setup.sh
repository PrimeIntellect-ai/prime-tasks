#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip cron
    pip3 install pytest

    mkdir -p /home/user/raw_data
    mkdir -p /home/user/clean_data

    python3 -c '
import os

os.makedirs("/home/user/raw_data", exist_ok=True)

# File 1: UTF-8
with open("/home/user/raw_data/file1.txt", "w", encoding="utf-8") as f:
    f.write("Hello World\n")
    f.write("Data Science\n")
    f.write("Café\n") # NFC by default usually

# File 2: ISO-8859-1
with open("/home/user/raw_data/file2.txt", "w", encoding="iso-8859-1") as f:
    f.write("Hola\n")
    f.write("Caf\xe9\n") # Café in latin-1
    f.write("Python\n")

# File 3: UTF-16LE
with open("/home/user/raw_data/file3.txt", "w", encoding="utf-16le") as f:
    f.write("Hello World\n") # Duplicate
    f.write("おはよう\n")
    f.write("Cafe\u0301\n") # NFD Café -> should normalize to Café and deduplicate
'

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/raw_data /home/user/clean_data
    chmod -R 777 /home/user
