#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip redis-server redis-tools curl jq gawk sed cron
    pip3 install pytest flask

    mkdir -p /app/services

    # Create the Flask API
    cat << 'EOF' > /app/services/api.py
from flask import Flask, Response
import json
import random

app = Flask(__name__)

@app.route('/logs')
def logs():
    def generate():
        user_types = ['guest', 'registered', 'admin']
        events = ['  User CLICKED! ', 'Logged IN.', 'Error 404...', '  Purchased item!']
        for i in range(10000):
            yield json.dumps({
                "timestamp": f"2023-10-01T{random.randint(0,23):02d}:{random.randint(0,59):02d}:10Z",
                "user_id": str(random.randint(1000, 9999)),
                "event_text": random.choice(events),
                "user_type": random.choice(user_types)
            }) + "\n"
    return Response(generate(), mimetype='application/json')

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
EOF

    # Create the start script
    cat << 'EOF' > /app/services/start.sh
#!/bin/bash
service cron start
redis-server --daemonize yes
nohup python3 /app/services/api.py > /dev/null 2>&1 &

sleep 2
# Populate redis with some random user categories
for i in {1000..9999}; do
    cat=$((RANDOM % 4))
    if [ $cat -eq 0 ]; then
        redis-cli set user:$i premium > /dev/null
    elif [ $cat -eq 1 ]; then
        redis-cli set user:$i standard > /dev/null
    elif [ $cat -eq 2 ]; then
        redis-cli set user:$i spam > /dev/null
    fi
done
EOF
    chmod +x /app/services/start.sh

    # Create the verifier script
    cat << 'EOF' > /app/verifier.py
import csv, os, re, subprocess

def verify():
    score = 0.0
    try:
        with open('/home/user/cleaned_dataset.csv', 'r') as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        counts = {'guest': 0, 'registered': 0, 'admin': 0}
        hour_ok = 0
        clean_ok = 0
        cat_ok = 0

        for r in rows:
            counts[r['user_type']] = counts.get(r['user_type'], 0) + 1
            if r['hour'].isdigit() and 0 <= int(r['hour']) <= 23:
                hour_ok += 1
            if r['event_clean'] == r['event_clean'].lower().strip() and not re.search(r'[^\w\s]', r['event_clean']):
                clean_ok += 1
            if r['user_category'] in ['premium', 'standard', 'spam', 'unknown']:
                cat_ok += 1

        if counts == {'guest': 100, 'registered': 100, 'admin': 100}:
            score += 0.3

        if hour_ok == 300: score += 0.2
        if clean_ok == 300: score += 0.2
        if cat_ok == 300: score += 0.2

    except Exception:
        pass

    try:
        crontab = subprocess.check_output(['crontab', '-l']).decode()
        if '*/5 * * * *' in crontab and '/home/user/pipeline.sh' in crontab:
            score += 0.1
    except:
        pass

    print(score)

if __name__ == '__main__':
    verify()
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
