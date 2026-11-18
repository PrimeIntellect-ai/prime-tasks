#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3 fonts-dejavu-core
    pip3 install pytest

    # Create directories
    mkdir -p /app/build_state
    mkdir -p /app/verifier_assets/evil
    mkdir -p /app/verifier_assets/clean

    # 1. Create the video
    ffmpeg -y -f lavfi -i color=c=black:s=640x480:d=6 -vf "drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:text='error while loading shared libraries\: liblegacy_parser.so.4\: cannot open shared object file\: No such file or directory':fontcolor=white:fontsize=16:x=10:y=10:enable='between(n,120,150)'" /app/ci_screen.mp4

    # 2. Create the SQLite DB and WAL
    sqlite3 /app/build_state/cache.db "PRAGMA journal_mode=WAL; CREATE TABLE processed_files(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO processed_files(name) VALUES ('asset_8920.asset'); INSERT INTO processed_files(name) VALUES ('asset_8921.asset');"
    # Ensure WAL file exists (sqlite3 might clean it up on exit, so touch it if missing)
    touch /app/build_state/cache.db-wal

    # 3. Create the core dump
    echo -e "\x00\x01\x02\x03[[[MACRO_EXP_OVERFLOW_0x7F_FATAL]]]\x04\x05\x06" > /app/build_state/core.dump

    # 4. Create verifier assets
    echo "This is an evil file with [[[MACRO_EXP_OVERFLOW_0x7F_FATAL]]] inside." > /app/verifier_assets/evil/evil1.asset
    echo "Another evil [[[MACRO_EXP_OVERFLOW_0x7F_FATAL]]] file." > /app/verifier_assets/evil/evil2.asset
    echo "This is a clean file with [[[MACRO_SAFE]]] inside." > /app/verifier_assets/clean/clean1.asset
    echo "Just some random text." > /app/verifier_assets/clean/clean2.asset

    # Create user
    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
