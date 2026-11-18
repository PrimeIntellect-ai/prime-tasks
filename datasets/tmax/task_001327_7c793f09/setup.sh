#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        sqlite3 \
        socat \
        netcat-openbsd \
        jq \
        curl

    pip3 install pytest

    useradd -m -s /bin/bash user || true

    mkdir -p /app

    # Create dummy audio and model files
    touch /app/pending_interview.wav
    touch /app/ggml-tiny.en.bin

    # Create a fake whisper-cli that outputs the expected transcript
    cat << 'EOF' > /app/whisper-cli
#!/bin/bash
echo "[00:00:00.000 --> 00:00:05.000] The canopy density in this region has increased significantly since the last survey."
EOF
    chmod +x /app/whisper-cli

    # Create the database and populate it
    cat << 'EOF' > /tmp/setup_db.py
import sqlite3
import random

conn = sqlite3.connect('/home/user/research_data.db')
c = conn.cursor()
c.execute("CREATE TABLE interviews (id INTEGER PRIMARY KEY, date TEXT, location TEXT, duration_seconds INTEGER, status TEXT);")
c.execute("CREATE TABLE tags (id INTEGER PRIMARY KEY, tag_name TEXT);")
c.execute("CREATE TABLE interview_tags (interview_id INTEGER, tag_id INTEGER);")

c.execute("INSERT INTO tags (id, tag_name) VALUES (1, 'biodiversity'), (2, 'climate'), (3, 'deforestation');")
c.execute("INSERT INTO interviews (id, date, location, duration_seconds, status) VALUES (42, '2023-10-12', 'Amazonas', 3600, 'pending_transcription');")
c.execute("INSERT INTO interview_tags (interview_id, tag_id) VALUES (42, 1);")

interviews = []
interview_tags = []
for i in range(100, 50100):
    interviews.append((i, '2023-10-12', 'Other', 1000, 'done'))
    interview_tags.append((i, random.choice([1,2,3])))

c.executemany("INSERT INTO interviews (id, date, location, duration_seconds, status) VALUES (?, ?, ?, ?, ?)", interviews)
c.executemany("INSERT INTO interview_tags (interview_id, tag_id) VALUES (?, ?)", interview_tags)
conn.commit()
conn.close()
EOF

    python3 /tmp/setup_db.py
    rm /tmp/setup_db.py

    chown -R user:user /home/user
    chmod -R 777 /home/user
