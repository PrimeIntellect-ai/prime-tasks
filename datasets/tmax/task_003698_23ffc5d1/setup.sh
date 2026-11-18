#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc build-essential
    pip3 install pytest

    mkdir -p /app/corpus/clean/case_01
    echo "[2023-01-01 12:00:00] log entry" > /app/corpus/clean/case_01/log.txt

    mkdir -p /app/corpus/evil/case_01_loop
    ln -s loop2 /app/corpus/evil/case_01_loop/loop1
    ln -s loop1 /app/corpus/evil/case_01_loop/loop2

    mkdir -p /app/corpus/evil/case_02_escape
    ln -s /etc/passwd /app/corpus/evil/case_02_escape/escape

    mkdir -p /app/corpus/evil/case_03_hardlink
    echo "test" > /app/corpus/evil/case_03_hardlink/file1
    ln /app/corpus/evil/case_03_hardlink/file1 /app/corpus/evil/case_03_hardlink/file2

    mkdir -p /app/corpus/evil/case_04_long
    echo "[2023-01-01 12:00:00] start" > /app/corpus/evil/case_04_long/log.txt
    for i in $(seq 1 51); do echo "line $i" >> /app/corpus/evil/case_04_long/log.txt; done

    mkdir -p /app/corpus/evil/case_05_null
    printf "bad\0data" > /app/corpus/evil/case_05_null/log.txt

    echo "int main() { return 0; }" > /tmp/rotator.c
    gcc -o /app/legacy_rotator /tmp/rotator.c
    strip /app/legacy_rotator
    rm /tmp/rotator.c

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
