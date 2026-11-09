#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 espeak
    pip3 install pytest

    mkdir -p /app/corpus/evil
    mkdir -p /app/corpus/clean

    # Generate DB and WAL file. Force exit to avoid checkpointing the WAL file.
    python3 -c "
import sqlite3, os
conn = sqlite3.connect('/app/pipeline.db')
conn.execute('PRAGMA journal_mode=WAL')
conn.execute('CREATE TABLE logs(id INTEGER PRIMARY KEY, message TEXT)')
conn.execute(\"INSERT INTO logs (message) VALUES ('normal log 1')\")
conn.commit()
conn.execute('BEGIN TRANSACTION')
conn.execute(\"INSERT INTO logs (message) VALUES ('CRITICAL_VULN_a1b2c3d4')\")
os._exit(0)
"

    # Generate corpus files
    for i in $(seq 1 10); do
        echo "This is evil payload CRITICAL_VULN_1a2b3c4d inside the file." > /app/corpus/evil/file_$i.txt
        echo "This is clean log CRITICAL_VULN_ without the hex." > /app/corpus/clean/file_$i.txt
    done

    # Generate audio report
    espeak -w /app/bisect_report.wav "I finally bisected the regression. The crash occurs because of a catastrophic regex backtracking issue. I couldn't save the exact pattern, but the malicious payload is the very last uncommitted message inserted into the database WAL file right before the crash. Look in the WAL file. The payload always starts with the word 'CRITICAL_VULN_' followed immediately by exactly 8 hexadecimal characters. Write a detector that rejects any text containing this 'CRITICAL_VULN_' prefix followed by any 8 hex characters."

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
