#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ffmpeg sqlite3
    pip3 install pytest gTTS

    mkdir -p /app/data

    python3 -c "
import sqlite3
from gtts import gTTS

# Create database
conn = sqlite3.connect('/app/data/analytics.db')
c = conn.cursor()
c.execute('''CREATE TABLE events (
    event_id INTEGER PRIMARY KEY,
    user_id INTEGER,
    event_type TEXT,
    event_timestamp DATETIME,
    revenue REAL
)''')

# Insert mock data
# User 1: Total 650 (>500)
c.execute(\"INSERT INTO events (user_id, event_type, event_timestamp, revenue) VALUES (1, 'purchase', '2023-10-01 10:00:00', 300)\")
c.execute(\"INSERT INTO events (user_id, event_type, event_timestamp, revenue) VALUES (1, 'purchase', '2023-10-02 10:00:00', 350)\")

# User 2: Total 300 (<500)
c.execute(\"INSERT INTO events (user_id, event_type, event_timestamp, revenue) VALUES (2, 'purchase', '2023-10-01 11:00:00', 200)\")
c.execute(\"INSERT INTO events (user_id, event_type, event_timestamp, revenue) VALUES (2, 'purchase', '2023-10-02 11:00:00', 100)\")

conn.commit()
conn.close()

# Create audio instructions
text = 'Create a web server listening on port 8080. Expose an HTTP GET endpoint at /api/revenue_summary. The endpoint must return a JSON array containing the user_id, event_timestamp, and a cumulative sum of revenue per user ordered by event_timestamp. Only include users whose total revenue exceeds 500. Format the response as a list of JSON objects.'
tts = gTTS(text)
tts.save('/app/instructions.mp3')
"

    # Convert mp3 to wav
    ffmpeg -i /app/instructions.mp3 /app/instructions.wav
    rm /app/instructions.mp3

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
    chmod -R 777 /app
