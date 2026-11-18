#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip sqlite3 ffmpeg git make g++ wget
    pip3 install pytest gTTS

    # Build whisper.cpp
    mkdir -p /opt
    cd /opt
    git clone https://github.com/ggerganov/whisper.cpp.git
    cd whisper.cpp
    git checkout v1.5.4
    make
    bash ./models/download-ggml-model.sh tiny.en

    # Create /app and generate db
    mkdir -p /app
    cd /app

    cat << 'EOF' > create_db.py
import sqlite3
import random

conn = sqlite3.connect('/app/sales.db')
c = conn.cursor()
c.execute('CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT)')
c.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, customer_id INTEGER, amount REAL)')

for i in range(1, 201):
    c.execute('INSERT INTO customers (id, name) VALUES (?, ?)', (i, f'Customer_{i}'))

# Insert transactions
tx_id = 1
for i in range(1, 201):
    # some customers have only < 50
    if i % 10 == 0:
        for _ in range(5):
            c.execute('INSERT INTO transactions (tx_id, customer_id, amount) VALUES (?, ?, ?)', (tx_id, i, random.uniform(10.0, 49.99)))
            tx_id += 1
    else:
        for _ in range(5):
            c.execute('INSERT INTO transactions (tx_id, customer_id, amount) VALUES (?, ?, ?)', (tx_id, i, random.uniform(10.0, 200.0)))
            tx_id += 1

conn.commit()
conn.close()
EOF
    python3 create_db.py

    # Generate audio
    cat << 'EOF' > gen_audio.py
from gtts import gTTS
tts = gTTS("Please ignore any transactions with an amount strictly less than fifty dollars.")
tts.save("/app/analyst_note.mp3")
EOF
    python3 gen_audio.py
    ffmpeg -i /app/analyst_note.mp3 -ar 16000 -ac 1 -c:a pcm_s16le /app/analyst_note.wav
    rm /app/analyst_note.mp3

    # Create oracle
    cat << 'EOF' > /app/oracle_report.sh
#!/bin/bash
ID=$1
RES=$(sqlite3 /app/sales.db "SELECT c.name, COUNT(t.tx_id), IFNULL(SUM(t.amount), 0), IFNULL(AVG(t.amount), 0) FROM customers c LEFT JOIN transactions t ON c.id = t.customer_id AND t.amount >= 50 WHERE c.id = $ID GROUP BY c.id;")
if [ -z "$RES" ]; then
    exit 1
fi
NAME=$(echo "$RES" | cut -d'|' -f1)
COUNT=$(echo "$RES" | cut -d'|' -f2)
SUM=$(echo "$RES" | cut -d'|' -f3)
AVG=$(echo "$RES" | cut -d'|' -f4)

if [ "$COUNT" -eq 0 ]; then
    echo "Customer $NAME (ID: $ID): No valid transactions"
else
    printf "Customer %s (ID: %d): Total=%.2f, Avg=%.2f\n" "$NAME" "$ID" "$SUM" "$AVG"
fi
EOF
    chmod +x /app/oracle_report.sh

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
