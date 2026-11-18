#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak gcc curl openssl
    pip3 install pytest

    mkdir -p /app/corpora/clean /app/corpora/evil

    # Clean examples
    echo -n "update_v1.0.tar.gz" > /app/corpora/clean/1.txt
    echo -n "patch-kernel-5.15.diff" > /app/corpora/clean/2.txt
    echo -n "system_config_backup.bak" > /app/corpora/clean/3.txt

    # Evil examples
    echo -n "../../../etc/shadow" > /app/corpora/evil/1.txt
    echo -n "update.tar.gz; rm -rf /" > /app/corpora/evil/2.txt
    echo -n "payload.sh | bash" > /app/corpora/evil/3.txt
    echo -n "some/path/file.txt" > /app/corpora/evil/4.txt
    echo -n "valid_name_.._suffix" > /app/corpora/evil/5.txt

    # Generate voicemail
    espeak -w /app/voicemail.wav "Please configure the secure deployment server to use port eight four four three."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
