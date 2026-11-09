#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg

    # Install dependencies
    pip3 install pytest pandas gTTS whisper-ctranslate2

    # Create required directories
    mkdir -p /app
    useradd -m -s /bin/bash user || true

    # Generate the voicemail audio
    cat << 'EOF' > /tmp/gen_audio.py
from gtts import gTTS
import os

text = "We have a chain corruption. I need you to write a recursive CTE starting from job ID 10000 to find all its descendant jobs. Then, use a window function to calculate the cumulative sum of size_bytes ordered by start_time across this specific chain. Finally, filter the results to only include jobs where the status is FAILED, order them by the cumulative size descending, and return exactly the top 50 records. Include job_id, parent_job_id, status, and the cumulative_size."

tts = gTTS(text)
tts.save("/app/voicemail.mp3")
os.system("ffmpeg -i /app/voicemail.mp3 -ar 16000 /app/voicemail.wav -y")
os.remove("/app/voicemail.mp3")
EOF
    python3 /tmp/gen_audio.py

    # Generate the SQLite database
    cat << 'EOF' > /tmp/gen_db.py
import sqlite3
import random
from datetime import datetime, timedelta

conn = sqlite3.connect('/home/user/backups.db')
c = conn.cursor()
c.execute('''CREATE TABLE backup_jobs 
             (job_id INTEGER PRIMARY KEY, parent_job_id INTEGER, region TEXT, status TEXT, size_bytes INTEGER, start_time DATETIME)''')

rows = []
# Create a base tree
for i in range(1, 200000):
    parent = random.randint(1, i-1) if i > 1 else None
    if i == 10000:
        parent = None # Root of the target chain
    elif 10000 < i < 15000:
        # Force a deep chain for job 10000
        parent = random.randint(10000, i-1)

    status = random.choices(['SUCCESS', 'FAILED', 'RUNNING'], weights=[0.8, 0.18, 0.02])[0]
    size = random.randint(1024, 1073741824)
    start_time = datetime(2023, 1, 1) + timedelta(minutes=i)
    rows.append((i, parent, 'US-EAST', status, size, start_time.strftime("%Y-%m-%d %H:%M:%S")))

c.executemany('INSERT INTO backup_jobs VALUES (?, ?, ?, ?, ?, ?)', rows)
conn.commit()
conn.close()
EOF
    python3 /tmp/gen_db.py

    # Cleanup and permissions
    rm -f /tmp/gen_audio.py /tmp/gen_db.py
    chmod -R 777 /home/user /app
