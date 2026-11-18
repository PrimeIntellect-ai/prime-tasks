#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip espeak ffmpeg
    pip3 install pytest

    mkdir -p /app

    # Generate the audio file
    espeak -w /app/query.wav "Please find the shortest citation path from paper 105 to paper 402."

    # Create the database
    python3 -c "
import sqlite3
import os

os.makedirs('/app', exist_ok=True)
conn = sqlite3.connect('/app/citations.db')
c = conn.cursor()
c.execute('CREATE TABLE papers (id INTEGER PRIMARY KEY, title TEXT)')
c.execute('CREATE TABLE citations (source_id INTEGER, target_id INTEGER)')

papers = [
    (105, 'Graph Theory Basics'),
    (210, 'Advanced Network Analysis'),
    (315, 'Citation Dynamics'),
    (402, 'Predictive Modeling in Academia'),
    (999, 'Decoy Paper 1'),
    (888, 'Decoy Paper 2')
]
c.executemany('INSERT INTO papers VALUES (?, ?)', papers)

citations = [
    (105, 210),
    (210, 315),
    (315, 402),
    (105, 999),
    (999, 888),
    (210, 888)
]
c.executemany('INSERT INTO citations VALUES (?, ?)', citations)

conn.commit()
conn.close()
"

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
