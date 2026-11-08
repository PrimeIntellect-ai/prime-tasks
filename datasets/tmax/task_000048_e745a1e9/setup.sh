#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server jq curl gawk
    pip3 install pytest flask redis python-dotenv

    mkdir -p /app/services/flask /app/services/redis
    mkdir -p /app/corpora/clean /app/corpora/evil

    cat << 'EOF' > /app/services/flask/app.py
import os, json, uuid, random, string
from flask import Flask, jsonify
import redis
from dotenv import load_dotenv

load_dotenv('/app/services/flask/.env')
app = Flask(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', 'localhost'), port=int(os.getenv('REDIS_PORT', 6379)))

@app.route('/api/data')
def get_data():
    id_val = str(uuid.uuid4())
    # Generate some random text, sometimes evil, sometimes clean
    is_evil = random.choice([True, False])
    if is_evil:
        text = "Hello world! " + "\u200B" + " Hidden poison."
    else:
        text = "This is a perfectly clean string with some data. " + "".join(random.choices(string.ascii_letters, k=20))

    r.set(id_val, text) # store in redis just to ensure connection works
    return jsonify({"id": id_val, "text": text})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    cat << 'EOF' > /app/services/flask/.env
REDIS_HOST=
REDIS_PORT=
EOF

    cat << 'EOF' > /app/services/redis/redis.conf
port 6379
daemonize no
EOF

    cat << 'EOF' > /app/corpora/clean/clean1.txt
This is a standard text file. It has normal punctuation, like commas and periods. The ratio of punctuation to alphanumeric characters is very low.
EOF

    cat << 'EOF' > /app/corpora/clean/clean2.txt
Another clean example without any strange unicode or excessive symbols.
EOF

    echo -e "This looks normal but has a hidden\xe2\x80\x8b space." > /app/corpora/evil/evil1.txt

    cat << 'EOF' > /app/corpora/evil/evil2.txt
!!!!++++---- This file has way too many symbols! $$$$%%%%
EOF

    cat << 'EOF' > /app/corpora/evil/evil3.txt
!!! ??? ***
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user /app
