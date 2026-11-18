#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip gcc libsqlite3-dev sqlite3
    pip3 install pytest

    useradd -m -s /bin/bash user || true

    cat << 'EOF' > /home/user/generate_csv.py
import random
import datetime

random.seed(42)
event_types = ['view', 'click', 'purchase', 'add_to_cart']

with open("/home/user/raw_events.csv", "w") as f:
    for i in range(5000):
        ts = datetime.datetime(2023, 1, 1) + datetime.timedelta(minutes=i)
        user_id = random.randint(1, 100)
        event = random.choice(event_types)
        price = round(random.uniform(5.0, 500.0), 2) if event == 'purchase' else 0.0
        f.write(f"{ts.isoformat()},{user_id},{event},{price}\n")
EOF
    python3 /home/user/generate_csv.py

    chmod -R 777 /home/user
