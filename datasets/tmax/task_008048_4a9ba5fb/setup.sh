#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip tar gzip coreutils
    pip3 install pytest

    mkdir -p /home/user/incoming
    mkdir -p /home/user/extracted
    mkdir -p /home/user/clean_source

    mkdir -p /tmp/setup_source
    cd /tmp/setup_source

    echo "Привет, мир! Это файл A." | iconv -f UTF-8 -t WINDOWS-1251 > fileA.txt
    echo "Тестовая строка для файла B." | iconv -f UTF-8 -t WINDOWS-1251 > fileB.txt
    echo "Этот файл будет поврежден." | iconv -f UTF-8 -t WINDOWS-1251 > fileC.txt

    md5sum fileA.txt fileB.txt fileC.txt > checksums.md5

    echo "CORRUPTED DATA" >> fileC.txt

    tar -cf source_files.tar fileA.txt fileB.txt fileC.txt

    tar -cf - source_files.tar checksums.md5 | gzip | base64 | rev > /home/user/incoming/project.cgar

    cd /
    rm -rf /tmp/setup_source

    useradd -m -s /bin/bash user || true
    chown -R user:user /home/user/incoming /home/user/extracted /home/user/clean_source
    chmod -R 777 /home/user
